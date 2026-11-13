class GamesController < ApplicationController
  before_action :authenticate_user!

  def new; end

  def create
    game = Game.create!(
      user: current_user,
      dimension: 10
    )

    dimension_params = [].tap do |array|
      (1..game.dimension).each do |y|
        (1..game.dimension).each do |x|
          array << {
            x: x,
            y: y
          }
        end
      end
    end

    game.cells.create(dimension_params)

    render json: { game: game.as_json }
  end

  def show
    game = Game.find params[:id]
    gamers = game.gamers

    if !(current_user.id.in?(gamers.map(&:user_id))) && gamers.size < 2
      game.gamers.create(user: current_user)
      game.reload

      broadcast game
    end

    render json: GameSerializer.render_as_hash(game)
  end

  def make_step
    game = Game.find params[:id]
    gamer = game.gamers.find_by(user_id: current_user.id)
    cell = Cell.find(params[:cell][:id])

    kind = game.steps.any? ? :o : :x
    gamer.update(kind: kind) unless gamer.kind

    game.steps.create(
      cell_id: cell.id,
      gamer_id: gamer.id
    )
    cell.update(kind: gamer.kind)

    winner = Games::Logic::Win.perform game
    game.update(state: :finished, winner: winner) if winner

    if game.state == 'started' && game.cells.where.not(kind: nil).count > 75
      draw = Games::Logic::Draw.perform(game)

      game.update(state: :finished) if draw
    end

    broadcast game
  end

  private

  def broadcast(game)
    ActionCable.server.broadcast "Game_#{game.id}", { game: GameSerializer.render_as_hash(game) }
  end
end
