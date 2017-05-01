require 'sinatra'
require 'sinatra/reloader' if development?
require 'tilt/erubis'

configure do
  enable :sessions
  set :session_secret, 'secret'
end

get '/' do
  session[:message] = nil

  erb :index
end

get '/instructions' do
  erb :instructions
end

# effectively becomes my initialize of the game orchestration engine
get '/enter' do
  session[:dungeon] = Dungeon.new
  session[:player] = Player.new
  session[:game_over] = nil
  session[:message] = nil
  session[:wumpus_awake] = nil

  redirect '/dungeon'
end

get '/dungeon' do
  session[:game_over] = :out_of_arrows if session[:player].out_of_arrows?
  redirect '/game_over' if session[:game_over]
  @adjacent_rooms = session[:dungeon].player_adjacent
  @player_location = session[:dungeon].player_location
  @nearby_hazards = session[:dungeon].nearby_hazards_text

  erb :dungeon
end

get '/dungeon/:room' do
  session[:move_to_room] = params[:room]
  session[:message] =
    "You moved from cave #{session[:dungeon].player_location}."
  session[:dungeon].player_move(session[:move_to_room])

  redirect 'resolve_move'
end

get '/resolve_move' do
  hazard = session[:dungeon].hazard_at_player_location
  session[:wumpus_awake] = wumpus_wakes? unless ENV['RACK_ENV'] == 'test'

  case hazard
  when :wumpus
    if session[:wumpus_awake]
      session[:dungeon].wumpus_move
    else
      session[:game_over] = :wumpus
    end
  when :pit
    session[:game_over] = :pit
  when :bat
    session[:dungeon].player_bat_move
    session[:message] = 'Superbat grabbed you and carried you off!'
    redirect '/resolve_move'
  end

  redirect '/dungeon'
end

get '/game_over' do
  session[:message] = case session[:game_over]
                      when :wumpus
                        'The wumpus got you.'
                      when :pit
                        'You fell into a bottomless pit.'
                      when :got_wumpus
                        'Your arrow flies true! You got the wumpus!'
                      when :wumpus_move
                        'Your arrow woke the wumps. It found you!'
                      when :arrow_self
                        'You shot yourself.'
                      when :out_of_arrows
                        'You ran out of arrows.'
                      end

  erb :game_over
end

get '/arrow' do
  @max_rooms = 5

  erb :arrow
end

get '/arrow/:rooms' do
  @rooms_to_select = params[:rooms].to_i
  @player_room = session[:dungeon].player_location

  erb :arrow_rooms
end

def check_for_hit(room_shot_into)
  if room_shot_into == session[:dungeon].player_location
    session[:game_over] = :arrow_self
  elsif room_shot_into == session[:dungeon].wumpus_location
    session[:game_over] = :got_wumpus
  end
end

def resolve_arrow(arrow_path, current_room)
  arrow_path.each do |target_room|
    if session[:dungeon].adjacent_rooms?(current_room, target_room)
      current_room = target_room
      break if check_for_hit(current_room)
    else
      current_room = session[:dungeon].random_adjacent_room(current_room)
      check_for_hit(current_room)
      break
    end
  end
end

def wumpus_wakes?
  [0, 0, 0, 1].sample.zero?
end

def set_wumpus_wakes
  session[:wumpus_awake] = wumpus_wakes? unless ENV['RACK_ENV'] == 'test'
end

def wumpus_move_after_arrow
  set_wumpus_wakes
  session[:dungeon].wumpus_move if session[:wumpus_awake]
  session[:game_over] = :wumpus_move if
    session[:dungeon].wumpus_location == session[:dungeon].player_location
end

post '/arrow' do
  session[:player].use_arrow
  session[:message] =
    'Your arrow hits nothing. ' \
    "You have #{session[:player].arrow_count} arrows left."
  arrow_path = params[:target_1],
               params[:target_2],
               params[:target_3],
               params[:target_4],
               params[:target_5]
  arrow_path = arrow_path.compact.map(&:to_i)
  current_room = session[:dungeon].player_location

  resolve_arrow(arrow_path, current_room)
  wumpus_move_after_arrow unless session[:game_over] == :got_wumpus

  redirect '/dungeon'
end

# keeps track of how many arrows the player has left
class Player
  def initialize
    @arrows = 5
  end

  def use_arrow
    @arrows -= 1
  end

  def out_of_arrows?
    @arrows < 1
  end

  def arrow_count
    @arrows
  end
end

ROOM_CONNECTIONS = [
  [2, 5, 6],
  [1, 3, 7],
  [2, 4, 8],
  [3, 5, 9],
  [4, 1, 10],
  [1, 16, 20],
  [2, 16, 17],
  [3, 17, 18],
  [4, 18, 19],
  [5, 19, 20],
  [16, 15, 12],
  [17, 11, 13],
  [18, 12, 14],
  [19, 13, 15],
  [20, 14, 11],
  [6, 7, 11],
  [7, 8, 12],
  [8, 9, 13],
  [9, 10, 14],
  [6, 10, 15]
].freeze

ROOM_NUMBERS = (1..20).to_a

# Dungeon contains all of the rooms, connections, and contents thereof
class Dungeon
  # Room connections are based on a dodecahedron, with labels being index + 1
  def initialize
    reset
  end

  def reset
    self.rooms = room_reset
    populate_dungeon
  end

  def room_reset
    output = {}
    ROOM_NUMBERS.each do |room_number|
      output[room_number] =
        { adjacent: ROOM_CONNECTIONS[room_number - 1], contents: [] }
    end
    output
  end

  def valid_room?(room)
    ROOM_NUMBERS.include?(room)
  end

  def populate_dungeon
    population = [:player, :wumpus, :pit, :pit, :bat, :bat]
    room_numbers = ROOM_NUMBERS.shuffle
    rooms_to_populate = room_numbers.take(population.count)

    rooms_to_populate.each.with_index do |room, index|
      rooms[room][:contents] << population[index]
    end
  end

  def adjacent_rooms?(room1, room2)
    rooms[room1][:adjacent].include?(room2)
  end

  def random_adjacent_room(room)
    rooms[room][:adjacent].sample
  end

  def move(object, from, to)
    rooms[from][:contents].delete(object)
    rooms[to][:contents] << object
  end

  def location(object)
    rooms.each do |room, properties|
      return room if properties[:contents].include?(object)
    end
  end

  def wumpus_location
    location(:wumpus)
  end

  def wumpus_move
    new_wumpus_room = random_adjacent_room(wumpus_location)
    move(:wumpus, wumpus_location, new_wumpus_room)
  end

  def player_location
    location(:player)
  end

  def change_player_location(target_room)
    move(:player, player_location, target_room)
  end

  def player_adjacent
    rooms[player_location][:adjacent]
  end

  def player_move(room)
    room = room.to_i
    change_player_location(room) if player_adjacent.include?(room)
  end

  def player_bat_move
    possible_locations = (ROOM_NUMBERS - [player_location]).shuffle
    change_player_location(possible_locations.first)
  end

  def nearby_hazards_text
    adjacent_warnings = []
    player_adjacent.each { |room| adjacent_warnings += warnings(room) }
    adjacent_warnings.delete(nil)
    adjacent_warnings << "I don't sense anything nearby." if
      adjacent_warnings.empty?
    adjacent_warnings.uniq.join(' ')
  end

  def hazard_at_player_location
    hazards = []
    rooms[player_location][:contents].each do |hazard|
      hazards << hazard unless hazard == :player
    end
    hazards.first
  end

  attr_accessor :rooms

  def warnings(room)
    warnings = []
    rooms[room][:contents].each do |content|
      case content
      when :wumpus then warnings << "'I smell a wumpus.'"
      when :pit then warnings << "'I feel a draft.'"
      when :bat then warnings << "'I can hear bats nearby.'"
      end
    end
    warnings
  end
end
