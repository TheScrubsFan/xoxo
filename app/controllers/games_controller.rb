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
    cell = params[:cell]
    cell_id = cell[:id] if cell.is_a?(ActionController::Parameters)
    Games::MakeStep.call(game: game, user: current_user, cell_id: cell_id)
    broadcast game
  rescue Games::MakeStep::InvalidMove => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  private

  def broadcast(game)
    ActionCable.server.broadcast "Game_#{game.id}", { game: GameSerializer.render_as_hash(game) }
  end
end
