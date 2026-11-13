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
    assert_equal owner.id, body.fetch('current_gamer').fetch('user_id')
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

  test 'two players alternate until the owner wins and further moves are rejected' do
    owner = User.create!(email: 'match-owner@example.com', password: 'password123')
    opponent = User.create!(email: 'match-opponent@example.com', password: 'password123')
    game = Game.create!(user: owner, dimension: 10)
    owner_gamer = game.gamers.create!(user: owner)
    opponent_gamer = game.gamers.create!(user: opponent)
    (1..10).each { |y| (1..10).each { |x| game.cells.create!(x: x, y: y) } }
    moves = [[owner, 1, 1, 'x'], [opponent, 1, 2, 'o'],
             [owner, 2, 1, 'x'], [opponent, 2, 2, 'o'],
             [owner, 3, 1, 'x'], [opponent, 3, 2, 'o'],
             [owner, 4, 1, 'x'], [opponent, 4, 2, 'o'],
             [owner, 5, 1, 'x']]

    moves.each_with_index do |(user, x, y, kind), index|
      sign_in user
      cell = game.cells.find_by!(x: x, y: y)
      assert_broadcasts("Game_#{game.id}", 1) do
        post make_step_game_path(game), params: { cell: { id: cell.id } }, as: :json
      end
      assert_response :success
      assert_equal kind, cell.reload.kind
      assert_equal index + 1, game.steps.count
      assert_equal user.id, game.steps.order(:id).last.gamer.user_id
      message = JSON.parse(ActionCable.server.pubsub.broadcasts("Game_#{game.id}").last).fetch('game')
      assert_equal kind, message.fetch('cells')[y - 1][x - 1].fetch('kind')
      if index < 8
        assert_equal(index.even? ? opponent_gamer.id : owner_gamer.id, game.reload.current_gamer.id)
      else
        assert_equal 'finished', game.reload.state
        assert_equal owner_gamer.id, game.winner_id
        assert_equal owner_gamer.id, message.fetch('winner').fetch('id')
      end
      sign_out user
    end

    sign_in opponent
    assert_no_difference('Step.count') do
      assert_no_broadcasts("Game_#{game.id}") do
        post make_step_game_path(game), params: { cell: { id: game.cells.find_by!(x: 6, y: 1).id } }, as: :json
      end
    end
    assert_response :unprocessable_entity
  end
end
