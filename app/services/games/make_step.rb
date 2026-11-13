module Games
  class MakeStep
    class InvalidMove < StandardError; end

    def self.call(game:, user:, cell_id:)
      game.with_lock do
        gamer = game.gamers.find_by(user_id: user.id)
        raise InvalidMove, 'Ход недоступен' unless game.state == 'started' && game.gamers.count == 2 && gamer
        raise InvalidMove, 'Сейчас ход другого игрока' unless game.current_gamer&.id == gamer.id
        raise InvalidMove, 'Некорректная клетка' unless cell_id.to_s.match?(/\A[1-9]\d*\z/)

        cell = game.cells.find_by(id: cell_id)
        raise InvalidMove, 'Клетка недоступна' unless cell && cell.kind.nil?

        gamer.update!(kind: game.steps.exists? ? :o : :x) unless gamer.kind
        game.steps.create!(cell: cell, gamer: gamer)
        cell.update!(kind: gamer.kind)

        winner = Games::Logic::Win.perform(game)
        game.update!(state: :finished, winner: winner) if winner
        if game.state == 'started' && game.cells.where.not(kind: nil).count > 75
          game.update!(state: :finished) if Games::Logic::Draw.perform(game)
        end
      end
      game
    end
  end
end
