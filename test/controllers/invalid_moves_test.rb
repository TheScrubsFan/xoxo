require 'test_helper'

class InvalidMovesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionCable::TestHelper

  setup do
    @owner = User.create!(email: 'owner-invalid@example.com', password: 'password123')
    @opponent = User.create!(email: 'opponent-invalid@example.com', password: 'password123')
    @spectator = User.create!(email: 'spectator-invalid@example.com', password: 'password123')
    @game = Game.create!(user: @owner, dimension: 10)
    @game.gamers.create!(user: @owner)
    @game.gamers.create!(user: @opponent)
    @cell = @game.cells.create!(x: 1, y: 1)
  end

  def assert_rejected(user, params)
    sign_in user
    before = [Game.order(:id).map(&:attributes), Gamer.order(:id).map(&:attributes),
              Cell.order(:id).map(&:attributes), Step.order(:id).map(&:attributes)]
    assert_no_broadcasts("Game_#{@game.id}") do
      post make_step_game_path(@game), params: params, as: :json
    end
    assert_response :unprocessable_entity
    assert response.parsed_body.fetch('error').present?
    assert_equal before, [Game.order(:id).map(&:attributes), Gamer.order(:id).map(&:attributes),
                          Cell.order(:id).map(&:attributes), Step.order(:id).map(&:attributes)]
  end

  test 'spectator cannot move' do
    assert_rejected(@spectator, cell: { id: @cell.id })
  end

  test 'opponent cannot move first' do
    assert_rejected(@opponent, cell: { id: @cell.id })
  end

  test 'a player cannot move before the opponent joins' do
    @game.gamers.find_by!(user: @opponent).destroy!
    assert_rejected(@owner, cell: { id: @cell.id })
  end

  test 'occupied cell cannot be played' do
    @cell.update!(kind: :o)
    assert_rejected(@owner, cell: { id: @cell.id })
  end

  test 'cell from another game cannot be played' do
    other = Game.create!(user: @owner, dimension: 10)
    other_cell = other.cells.create!(x: 1, y: 1)
    assert_rejected(@owner, cell: { id: other_cell.id })
  end

  test 'finished games cannot be played' do
    @game.update!(state: :finished)
    assert_rejected(@owner, cell: { id: @cell.id })
  end

  test 'missing cell cannot be played' do
    assert_rejected(@owner, {})
  end

  test 'invalid cell identifier cannot be played' do
    assert_rejected(@owner, cell: { id: 'invalid' })
  end

  test 'out of range cell identifier cannot be played' do
    assert_rejected(@owner, cell: { id: '9999999999999999999999999999999999999999' })
  end

  test 'failed persistence does not broadcast or leave a partial move' do
    Cell.define_method(:fail_test_cell_update) { raise 'cell write failed' if id == Thread.current[:failing_cell_id] }
    Cell.set_callback(:update, :before, :fail_test_cell_update)
    Thread.current[:failing_cell_id] = @cell.id
    sign_in @owner
    assert_no_broadcasts("Game_#{@game.id}") do
      assert_raises(RuntimeError) do
        post make_step_game_path(@game), params: { cell: { id: @cell.id } }, as: :json
      end
    end
    assert_nil @game.gamers.find_by!(user: @owner).kind
    assert_nil @cell.reload.kind
    assert_equal 0, @game.steps.count
  ensure
    Thread.current[:failing_cell_id] = nil
    Cell.skip_callback(:update, :before, :fail_test_cell_update)
    Cell.remove_method(:fail_test_cell_update)
  end
end
