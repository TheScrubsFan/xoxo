require 'test_helper'

class GamesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  test 'creating a game returns its id and creates a ten by ten board' do
    user = User.create!(email: 'player@example.com', password: 'password123')
    sign_in user

    assert_difference('Game.count', 1) do
      assert_difference('Cell.count', 100) do
        post games_path, as: :json
      end
    end

    assert_response :success
    game = Game.find(response.parsed_body.fetch('game').fetch('id'))
    assert_equal user.id, game.user_id
    assert_equal 10, game.dimension
    assert_equal (1..10).to_a.product((1..10).to_a).sort,
                 game.cells.pluck(:x, :y).sort
  end

  test 'players join once and later visitors remain spectators' do
    owner = User.create!(email: 'owner@example.com', password: 'password123')
    second = User.create!(email: 'second@example.com', password: 'password123')
    spectator = User.create!(email: 'spectator@example.com', password: 'password123')
    game = Game.create!(user: owner, dimension: 10)
    game.cells.create!(x: 1, y: 1)

    sign_in owner
    assert_difference('Gamer.count', 1) { get game_path(game), as: :json }
    assert_response :success
    assert_no_difference('Gamer.count') { get game_path(game), as: :json }

    sign_out owner
    sign_in second
    assert_difference('Gamer.count', 1) do
      assert_broadcasts("Game_#{game.id}", 1) { get game_path(game), as: :json }
    end
    assert_response :success
    body = response.parsed_body
    assert_equal game.id, body.fetch('id')
    assert_equal [owner.id, second.id].sort, body.fetch('gamers').map { |gamer| gamer.fetch('user').fetch('id') }.sort
    assert_equal 1, body.fetch('cells').first.first.fetch('x')
    message = JSON.parse(ActionCable.server.pubsub.broadcasts("Game_#{game.id}").last)
    assert_equal game.id, message.fetch('game').fetch('id')
    assert_equal 1, message.fetch('game').fetch('cells').first.first.fetch('x')

    sign_out second
    sign_in spectator
    assert_no_difference('Gamer.count') { get game_path(game), as: :json }
    assert_response :success
  end

  test 'a move saves its history and broadcasts the updated board' do
    owner = User.create!(email: 'mover@example.com', password: 'password123')
    opponent = User.create!(email: 'opponent@example.com', password: 'password123')
    game = Game.create!(user: owner, dimension: 10)
    gamer = game.gamers.create!(user: owner)
    game.gamers.create!(user: opponent)
    cell = game.cells.create!(x: 1, y: 1)
    sign_in owner

    assert_difference('Step.count', 1) do
      assert_broadcasts("Game_#{game.id}", 1) do
        post make_step_game_path(game), params: { cell: { id: cell.id } }, as: :json
      end
    end

    assert_response :success
    assert_equal 'x', cell.reload.kind
    assert_equal gamer.id, game.steps.last.gamer_id
    assert_equal cell.id, game.steps.last.cell_id
    message = JSON.parse(ActionCable.server.pubsub.broadcasts("Game_#{game.id}").last)
    assert_equal 'x', message.fetch('game').fetch('cells').first.first.fetch('kind')
  end

  test 'game routes require authentication' do
    assert_no_difference('Game.count') { post games_path, as: :json }
    assert_response :unauthorized
    get game_path(123), as: :json
    assert_response :unauthorized
    post make_step_game_path(123), params: { cell: { id: 1 } }, as: :json
    assert_response :unauthorized
  end

  test 'missing games raise record not found' do
    user = User.create!(email: 'reader@example.com', password: 'password123')
    sign_in user
    assert_raises(ActiveRecord::RecordNotFound) { get game_path(99999999), as: :json }
  end

  test 'the final move on a full board without five in a row finishes as a draw' do
    owner = User.create!(email: 'draw@example.com', password: 'password123')
    opponent = User.create!(email: 'draw-opponent@example.com', password: 'password123')
    game = Game.create!(user: owner, dimension: 10)
    game.gamers.create!(user: owner, kind: :x)
    game.gamers.create!(user: opponent, kind: :o)
    (1..10).each do |y|
      (1..10).each do |x|
        kind = [0, 1].include?((x + 2 * y) % 4) ? 'x' : 'o'
        game.cells.create!(x: x, y: y, kind: x == 1 && y == 1 ? nil : kind)
      end
    end
    cell = game.cells.find_by!(x: 1, y: 1)
    sign_in owner

    post make_step_game_path(game), params: { cell: { id: cell.id } }, as: :json

    assert_response :success
    assert_equal 'finished', game.reload.state
    assert_nil game.winner
  end
end
