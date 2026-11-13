require 'test_helper'

class MakeStepTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owner = User.create!(email: 'atomic-owner@example.com', password: 'password123')
    @opponent = User.create!(email: 'atomic-opponent@example.com', password: 'password123')
    @game = Game.create!(user: @owner, dimension: 10)
    @gamer = @game.gamers.create!(user: @owner)
    @game.gamers.create!(user: @opponent)
    @cell = @game.cells.create!(x: 1, y: 1)
  end

  teardown do
    Step.where(game_id: @game.id).delete_all
    Cell.where(game_id: @game.id).delete_all
    Gamer.where(game_id: @game.id).delete_all
    @game.delete
    User.where(id: [@owner.id, @opponent.id]).delete_all
  end

  test 'failed cell save rolls back the move and player symbol' do
    Cell.define_method(:fail_test_cell_update) { raise 'cell write failed' if id == Thread.current[:failing_cell_id] }
    Cell.set_callback(:update, :before, :fail_test_cell_update)
    Thread.current[:failing_cell_id] = @cell.id
    error = assert_raises(RuntimeError) { Games::MakeStep.call(game: @game, user: @owner, cell_id: @cell.id) }
    assert_equal 'cell write failed', error.message
    assert_nil @gamer.reload.kind
    assert_nil @cell.reload.kind
    assert_equal 0, @game.steps.count
    assert_equal 'started', @game.reload.state
  ensure
    Thread.current[:failing_cell_id] = nil
    Cell.skip_callback(:update, :before, :fail_test_cell_update)
    Cell.remove_method(:fail_test_cell_update)
  end

  test 'concurrent attempts serialize and only one succeeds' do
    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          game = Game.find(@game.id)
          user = User.find(@owner.id)
          ready << true
          start.pop
          begin
            Games::MakeStep.call(game: game, user: user, cell_id: @cell.id)
            :success
          rescue Games::MakeStep::InvalidMove
            :invalid
          end
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    assert_equal [:invalid, :success], threads.map(&:value).sort
    assert_equal 1, @game.steps.count
    assert_equal 'x', @cell.reload.kind
  end
end
