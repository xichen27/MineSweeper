require 'yaml'

class Game
  attr_writer :session_start
  attr_reader :board
  
  def initialize(name, dimensions = [9, 9])
    @board = Board.new(dimensions)
    @player = Player.new(name, self)
    @session_start = Time.now
    @time_passed = 0
    save
  end
  
  def leaderboard(time_taken)
    File.open("leaderboard", "w") do |f|
      f.puts "#{@player.name} => #{time_taken}"
    end
  end
  
  def add_to_leaderboard
    @@leaderboard[@player.name] = lapsed_time
  end
  
  def get_move
    action, position = @player.move
    if action == :f
      @board.rows[position[0]][position[1]].toggle_flag
    else
      @board.rows[position[0]][position[1]].reveal
    end
  end
  
  def turn
    until @board.over?
      @board.display
      get_move
      save
      @board.auto_complete
    end
    @board.display
    if @board.lost?
      puts "Try again"
    else
      time_taken = elapsed_time.to_i
      puts "You won!"
      puts "You took #{time_taken} seconds"
      leaderboard(time_taken)
      File.readlines("leaderboard") do |f|
        puts f
      end
    end
  end
  
  def elapsed_time
    @time_passed += Time.now - @session_start
  end
  
  def save
    elapsed_time
    File.open("saved_game", "w") do |f|
      f.puts self.to_yaml
    end
  end
  
  def self.load
    game = YAML.load_file("saved_game")
    game.session_start = Time.now
    game.turn
  end
end

class Board
  attr_reader :rows
  attr_accessor :flags
  
  def initialize(dimensions)
    @rows = build_rows(dimensions)
    set_mines(dimensions)
    @flags = 0
    @dimensions = dimensions
  end
  
  def build_rows(dimensions)
    rows = []
    (0...dimensions[0]).each do |i|
      row = []
      (0...dimensions[1]).each do |j|
        row << Tile.new(self, [i, j])
      end
      rows << row
    end
    rows
  end
  
  def set_mines(dimensions)
    mine_positions = []
    @mines = (dimensions[0] * dimensions[1]) / 8
    until mine_positions.length == @mines
      pos = [rand(dimensions[0]), rand(dimensions[1])]
      mine_positions << pos unless mine_positions.include?(pos)
    end
    mine_positions.each do |tile|
      @rows[tile[0]][tile[1]].set_mine
    end
  end
  
  def display
    board_display = []
    @rows.each do |row|
      display_row = []
      row.each do |tile|
        if tile.revealed
          display_row << reveal_display(tile)
        else
          display_row << unreveal_display(tile)
        end
      end
      board_display << display_row
    end
    puts "There are #{@mines} mines"
    puts "There are #{@flags} flags"
    board_display.each { |row| print row.to_s + "\n" } 
  end
  
  def auto_complete
    auto_reveal
    auto_flag
  end
  
  def auto_reveal
    if @mines == @flags
      puts "Would you like to reveal the remaining tiles? (y/n)"
      if gets.chomp == "y"
        each_tile do |tile|
          next if tile.flagged
          tile.reveal
        end
      end
    end
  end
  
  def auto_flag
    if @mines != @flags && @mines - @flags == unrevealed_tiles.length
      puts "Would you like to flag the remaining tiles? (y/n)"
      if gets.chomp == "y"
        unrevealed_tiles.each { |tile| tile.toggle_flag }
      end
    end
  end
  
  def unrevealed_tiles
    unrevealeds = []
    each_tile { |tile| unrevealeds << tile unless tile.revealed || 
                       tile.flagged }
    unrevealeds
  end
  
  def unreveal_display(tile)
    if tile.flagged
      return :FL
    else
      return :[]
    end
  end
  
  def reveal_display(tile)
    if tile.mined
      return :*
    else 
      count = tile.bomb_count
      return :__ if count == 0
      return count.to_s
    end
  end
   
  def over?
    lost? || won?
  end
  
  def lost?
    each_tile { |tile| return true if tile.revealed && tile.mined }
    false
  end
  
  def won?
    return false unless @flags == @mines
    each_tile { |tile| return false if !tile.revealed && !tile.flagged }
    true
  end

  def legal_position?(pos)
    pos[0].between?(0, @dimensions[0] - 1) && 
      pos[1].between?(0, @dimensions[1] - 1)
  end
  
  def each_tile(&prc)
    @rows.each do |row|
      row.each do |tile|
        prc.call(tile)
      end
    end
  end
  
end

class Tile
  attr_reader :board, :revealed, :flagged, :mined, :pos
  
  NEIGHBOR_DIRECTIONS = [
    [1, 0],
    [1, -1],
    [0, -1],
    [-1, -1],
    [-1, 0],
    [-1, 1],
    [0, 1],
    [1, 1]
  ]
  def initialize(board, pos)
    @board = board
    @revealed = false
    @flagged = false
    @mined = false
    @pos = pos
  end
  
  def toggle_flag
    if !revealed
      if @flagged
        @flagged = false
        @board.flags -= 1
      else
        @flagged = true
        @board.flags += 1
      end
    else
      puts "You cannot flag a revealed square"
    end
  end
  
  def reveal
    if !flagged
      @revealed = true
    
      if bomb_count == 0
        neighbours.each do |neighbour|
          neighbour.reveal unless neighbour.revealed
       end
      end
    else
      puts "You cannot reveal a flagged square; flag again to unflag"
    end
  end
  
  def set_mine
    @mined = true
  end
  
  def bomb_count
    count = 0
    self.neighbours.each do |tile|
      count += 1 if tile.mined
    end
    count
  end
  
  def neighbours
    neighbors = []
    NEIGHBOR_DIRECTIONS.each do |direction|
      x = @pos[1] + direction[1]
      y = @pos[0] + direction[0]
      if board.legal_position?([y, x])
        neighbors << @board.rows[y][x]
      end    
    end
    neighbors
  end
end

class Player
  attr_accessor :name
  
  def initialize (name, game)
    @name = name
    @game = game
  end
  
  def move
    puts "Choose to reveal (r) or flag (f) a tile."
    action = gets.chomp.to_sym
    until valid_action?(action)
      puts "Choose to reveal (r) or flag (f)"
      action = gets.chomp.to_sym
    end

    puts "Choose which tile to change"
    position = gets.chomp.split(", ").map {|i| i.to_i}
    until position.length == 2 && @game.board.legal_position?(position) 
      puts "Choose a valid position"
      position = gets.chomp.split(", ").map {|i| i.to_i}
    end
    [action, position]
  end
  
  def valid_action?(action)
    action == :r || action == :f
  end
end

if __FILE__ == $PROGRAM_NAME
  puts "Would you like to 1 start a new game 2 load an old game."
  input = gets.chomp
  if input == "1"
    puts "What's your name?"
    name = gets.chomp
    puts "Choose the size of your board."
    dimensions = gets.chomp.split(", ").map {|i| i.to_i}
    game = Game.new(name, dimensions)
    game.turn
  else 
    Game.load
  end
end
