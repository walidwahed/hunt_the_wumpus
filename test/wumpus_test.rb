ENV["RACK_ENV"] = "test"

require 'minitest/autorun'
require 'rack/test'

require_relative '../wumpus.rb'

class WumpusTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def session
    last_request.env['rack.session']
  end

  def count_content(type_to_count)
    dungeon = session[:dungeon]
    count = 0
    if type_to_count == nil
      dungeon.rooms.keys.each do |room|
        count += 1 if dungeon.rooms[room][:contents].empty?
      end
    else
      dungeon.rooms.keys.each do |room|
        count += 1 if dungeon.rooms[room][:contents].include?(type_to_count)
      end
    end
    count
  end

  def setup_player_next_to(hazard)
    session[:dungeon].rooms[1][:contents] = [:player]
    session[:dungeon].rooms[2][:contents] << hazard
  end

  def clear_dungeon
    cleared_dungeon = {}
    session[:dungeon].rooms.each do |room, properties|
      cleared_dungeon[room] = { adjacent: properties[:adjacent], contents: [] }
    end
    cleared_dungeon
  end

  def test_index_page
    get '/'

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['Content-Type']
    assert_includes last_response.body, "Wumpus"
  end

  def test_dungeon_setup
    get '/enter'

    assert_equal 302, last_response.status
    assert_equal 1, count_content(:wumpus)
    assert_equal 1, count_content(:player)
    assert_equal 2, count_content(:pit)
    assert_equal 2, count_content(:bat)
  end

  def test_dungeon_empty_rooms
    get '/enter'
    get '/dungeon'

    assert_equal 14, count_content(nil)
  end

  def test_dungeon_total_rooms
    get '/enter'
    get '/dungeon'

    assert_equal 20, session[:dungeon].rooms.keys.count
  end

  def test_dungeon_adjacent_rooms
    get '/enter'
    get '/dungeon'

    rooms = []
    session[:dungeon].rooms.values.each do |properties|
      rooms << properties[:adjacent]
    end

    assert_equal ROOM_CONNECTIONS, rooms
  end

  def test_warning_adjacent_to_wumpus
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]

    get '/dungeon', {}, {'rack.session' => {dungeon: test_dungeon} }

    assert_includes last_response.body, 'smell a wumpus'
  end

  def test_warning_adjacent_to_bat
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:bat)
    test_dungeon = session[:dungeon]

    get '/dungeon', {}, {'rack.session' => {dungeon: test_dungeon} }

    assert_includes last_response.body, 'bats nearby'
  end
  
  def test_warning_adjacent_to_pit
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:pit)
    test_dungeon = session[:dungeon]

    get '/dungeon', {}, {'rack.session' => {dungeon: test_dungeon} }

    assert_includes last_response.body, 'draft'
  end

  def test_multiple_warnings
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:pit)
    setup_player_next_to(:bat)
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]

    get '/dungeon', {}, {'rack.session' => {dungeon: test_dungeon} }

    assert_includes last_response.body, 'draft'
    assert_includes last_response.body, 'bats nearby'
    assert_includes last_response.body, 'smell a wumpus'
  end

  def test_move_message_no_hazard
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(nil)
    test_dungeon = session[:dungeon]

    get '/dungeon/2', {}, {'rack.session' => {dungeon: test_dungeon} }
    assert_equal 302, last_response.status
    assert_nil session[:game_over]

    get '/resolve_move'
    assert_equal 302, last_response.status
    assert_equal "You moved from cave 1.", session[:message]
    assert_nil session[:game_over]

    get '/dungeon'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You're now in cave 2."
    assert_nil session[:game_over]
  end

  def test_move_into_pit
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:pit)
    test_dungeon = session[:dungeon]

    get '/dungeon/2', {}, {'rack.session' => {dungeon: test_dungeon} }
    assert_equal 302, last_response.status

    get '/resolve_move'
    assert_equal 302, last_response.status
    assert_equal :pit, session[:game_over]
  end

  def test_move_into_bat
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:bat)
    test_dungeon = session[:dungeon]

    get '/dungeon/2', {}, {'rack.session' => {dungeon: test_dungeon} }
    assert_equal 302, last_response.status

    get '/resolve_move'
    assert_equal 302, last_response.status
    assert_equal 'Superbat grabbed you and carried you off!', session[:message]
    refute_equal 2, session[:dungeon].player_location
  end

  def test_move_into_wumpus_awake
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]

    get '/dungeon/2', {}, {'rack.session' => {dungeon: test_dungeon} }
    assert_equal 302, last_response.status

    get '/resolve_move', {}, {'rack.session' => {wumpus_awake: true}}
    assert_nil session[:game_over]
  end

  def test_move_into_wumpus_not_awake
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]

    get '/dungeon/2', {}, {'rack.session' => {dungeon: test_dungeon} }
    assert_equal 302, last_response.status

    get '/resolve_move', {}, {'rack.session' => {wumpus_awake: false}}
    assert_equal :wumpus, session[:game_over]
  end

  def test_arrow_page
    get '/enter'
    get '/arrow'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "How many caves would you like your arrow to pass through?"
  end

  def test_arrow_cave_select_page_for_3_caves
    get '/enter'
    get '/arrow/3'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Arrow flight path order - cave #3:"
    assert_includes last_response.body, %q(<button type="submit">Shoot!</button>)
  end

  def test_shoot_wumpus
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]
    test_player = session[:player]

    post 'arrow', {target_1: '2'}, {'rack.session' => {dungeon: test_dungeon, player: test_player}}
    assert_equal :got_wumpus, session[:game_over]
  end

  def test_shoot_self
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(nil)
    test_dungeon = session[:dungeon]
    test_player = session[:player]

    post 'arrow', {target_1: '5', target_2: '1'}, {'rack.session' => {dungeon: test_dungeon, player: test_player}}
    assert_equal :arrow_self, session[:game_over]
  end

  def test_shoot_miss
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:nil)
    test_dungeon = session[:dungeon]
    test_player = session[:player]

    post 'arrow', {target_1: '5'}, {'rack.session' => {dungeon: test_dungeon, player: test_player}}
    assert_nil session[:game_over]
    assert_equal "Your arrow hits nothing. You have 4 arrows left.", session[:message]
  end

  def test_shoot_miss_wumpus_wakes_up
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]
    test_player = session[:player]

    post 'arrow', {target_1: '5'}, {'rack.session' => {dungeon: test_dungeon, player: test_player, wumpus_awake: true}}
    refute_equal 2, session[:dungeon].wumpus_location
    if session[:dungeon].wumpus_location == 1
      assert_equal :wumpus_move, session[:game_over]
    else
      assert_nil session[:game_over]
    end
  end

  def test_shoot_miss_wumpus_no_wake
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:wumpus)
    test_dungeon = session[:dungeon]
    test_player = session[:player]

    post 'arrow', {target_1: '5'}, {'rack.session' => {dungeon: test_dungeon, player: test_player, wumpus_awake: false}}
    assert_equal 2, session[:dungeon].wumpus_location
    assert_nil session[:game_over]
  end

  def test_out_of_arrows
    get '/enter'

    session[:dungeon].rooms = clear_dungeon
    setup_player_next_to(:nil)
    test_dungeon = session[:dungeon]
    test_player = session[:player]
    5.times { test_player.use_arrow }

    get '/dungeon', {}, {'rack.session' => {dungeon: test_dungeon, player: test_player}}
    assert_equal :out_of_arrows, session[:game_over]
  end

  def test_game_over_redirect
    get '/dungeon', {}, {'rack.session' => {game_over: :wumpus, player: Player.new}}

    assert_equal 302, last_response.status
  end

  def test_game_over_wumpus
    get '/game_over', {}, {'rack.session' => {game_over: :wumpus}}

    assert_includes last_response.body, 'The wumpus got you.'
  end

  def test_game_over_pit
    get '/game_over', {}, {'rack.session' => {game_over: :pit}}

    assert_includes last_response.body, 'You fell into a bottomless pit.'
  end

  def test_game_over_got_wumpus
    get '/game_over', {}, {'rack.session' => {game_over: :got_wumpus}}

    assert_includes last_response.body, 'Your arrow flies true! You got the wumpus!'
  end

  def test_game_over_wumpus_move
    get '/game_over', {}, {'rack.session' => {game_over: :wumpus_move}}

    assert_includes last_response.body, 'Your arrow woke the wumps. It found you!'
  end

  def test_game_over_arrow_self
    get '/game_over', {}, {'rack.session' => {game_over: :arrow_self}}

    assert_includes last_response.body, 'You shot yourself.'
  end

  def test_game_over_out_of_arrows
    get '/game_over', {}, {'rack.session' => {game_over: :out_of_arrows}}

    assert_includes last_response.body, 'You ran out of arrows.'
  end

end