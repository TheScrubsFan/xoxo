require 'test_helper'

class GameLogicTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: 'logic@example.com', password: 'password123')
    @game = Game.create!(user: user, dimension: 10)
    @gamer = @game.gamers.create!(user: user, kind: :x)
    (1..10).each do |y|
      (1..10).each { |x| @game.cells.create!(x: x, y: y) }
    end
  end

  {
    'horizontal' => [[1, 3], [2, 3], [3, 3], [4, 3], [5, 3]],
    'vertical' => [[3, 1], [3, 2], [3, 3], [3, 4], [3, 5]],
    'descending diagonal' => [[1, 1], [2, 2], [3, 3], [4, 4], [5, 5]],
    'ascending diagonal' => [[5, 1], [4, 2], [3, 3], [2, 4], [1, 5]]
  }.each do |direction, coordinates|
    test "five marks win on the #{direction}" do
      coordinates.each { |x, y| @game.cells.find_by!(x: x, y: y).update!(kind: :x) }
      assert_equal @gamer, Games::Logic::Win.perform(@game)
    end
  end

  test 'four marks are not a win' do
    (1..4).each { |x| @game.cells.find_by!(x: x, y: 1).update!(kind: :x) }
    assert_nil Games::Logic::Win.perform(@game)
  end

  test 'a line with four marks and an empty cell is not a draw' do
    (1..4).each { |x| @game.cells.find_by!(x: x, y: 1).update!(kind: :x) }
    assert_not Games::Logic::Draw.perform(@game)
  end

  test 'a filled board has no available winning line' do
    @game.cells.update_all(kind: 'x')
    assert Games::Logic::Draw.perform(@game)
  end

  test 'a gap between four marks still permits a winning move' do
    @game.cells.each do |cell|
      cell.update!(kind: [0, 1].include?((cell.x + 2 * cell.y) % 4) ? :x : :o)
    end
    [1, 2, 4, 5].each { |x| @game.cells.find_by!(x: x, y: 1).update!(kind: :x) }
    @game.cells.find_by!(x: 3, y: 1).update!(kind: nil)
    assert_nil Games::Logic::Win.perform(@game)
    assert_not Games::Logic::Draw.perform(@game)
  end
end
