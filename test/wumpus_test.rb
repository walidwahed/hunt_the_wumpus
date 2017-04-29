# ENV["RACK_ENV"] = "test"

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
    dungeon.rooms.keys.each do |room|
      count += 1 if dungeon.rooms[room][:contents].include?(type_to_count)
    end
    count
  end

  def setup_player_next_to(hazard)
    session[:dungeon].rooms[1][:contents] << :player
    session[:dungeon].rooms[2][:contents] << hazard
  end

  def clear_dungeon
    cleared_dungeon = {}
    session[:dungeon].rooms.each do |room, properties|
      cleared_dungeon[room] = { adjacent: properties[:adjacent], contents: [] }
    end
    session[:dungeon].rooms = cleared_dungeon
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

  def test_player_next_to_wumpus
    # get '/enter'

    # # p session[:dungeon].rooms

    # cleared_dungeon = {}
    # session[:dungeon].rooms.each do |room, properties|
    #   cleared_dungeon[room] = { adjacent: properties[:adjacent], contents: [] }
    # end
    # session[:dungeon].rooms = cleared_dungeon

    # # p session[:dungeon].rooms
    # # setup_player_next_to(:wumpus)

    # # p session[:dungeon].rooms

    # get '/dungeon'

    # p session[:dungeon].rooms


    assert_includes last_response.body, "'I smell a wumpus.'"
  end
  
end