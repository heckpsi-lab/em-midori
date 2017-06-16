##
# Merge and manage all APIs.
# @attr [Hash] routes A hash of all routes merged
class Midori::APIEngine
  attr_accessor :routes

  # Init an API Engine
  # @param [Class] root_api API inherited from [Midori::API]
  # @param [Symbol] type type mustermann support
  def initialize(root_api, type = :sinatra)
    @routes = {}
    Midori::Const::ROUTE_METHODS.map {|method| @routes[method] = []}  
    @root_api = root_api
    @type = type
    @routes = merge('', root_api, [])
    @routes.delete :MOUNT
    @routes.each do |method|
      method[1].each do |route|
        route.path = Mustermann.new(route.path, type: type)
      end
    end
  end

  # Merge all routes with a Depth-first search
  private def merge(prefix, root_api, middlewares)
    root_api.routes[:MOUNT].each do |mount|
      root_api.routes.merge!(merge(mount[0], mount[1], root_api.scope_middlewares)) do |_key, old_val, new_val|
        old_val + new_val
      end
    end
    root_api.routes.delete :MOUNT
    root_api.routes.each do |method|
      method[1].each do |route|
        route.path = prefix + route.path
        route.middlewares = middlewares + route.middlewares
      end
    end
    root_api.routes
  end

  # Process after receive data from client
  # @param request [Midori::Request] Http Raw Request
  # @param connection [EM::Connection] A connection created by EventMachine
  # @return [Midori::Response] Http Response
  # @raise [Midori::Error::NotFound] If no route matched
  def receive(request, connection = nil)
    @routes[request.method].each do |route|
      params = route.path.params(request.path)
      next unless params # Skip if not matched
      request.params = params
      clean_room = Midori::CleanRoom.new(request)
      if request.websocket?
        # Send 101 Switching Protocol
        connection.send_data Midori::Response.new(
          status: 101,
          header: Midori::APIEngine.websocket_header(request.header['Sec-WebSocket-Key']),
          body: '')
        connection.websocket.request = request
        Midori::Sandbox.run(clean_room, route.function, connection.websocket)
        return Midori::Response.new
      elsif request.eventsource?
        connection.send_data Midori::Response.new(
          status: 200,
          header: Midori::Const::EVENTSOURCE_HEADER)
        Midori::Sandbox.run(clean_room, route.function, connection.eventsource)
        return Midori::Response.new
      else
        request = middleware_exec(route.middlewares, clean_room, request)
        return request if request.is_a? Midori::Response # Early stop
        result = Midori::Sandbox.run(clean_room, route.function)
        clean_room.body = result
        response = result.is_a?(Midori::Response) ? result : clean_room.raw_response
        response = middleware_exec(route.middlewares, clean_room, request, response)
        return response
      end
    end
    raise Midori::Exception::NotFound
  end

  # Return websocket header with given key
  # @param [String] key 'Sec-WebSocket-Key' in request header
  # @return [Hash] header
  def self.websocket_header(key)
    header = Midori::Const::WEBSOCKET_HEADER.clone
    header['Sec-WebSocket-Accept'] = Digest::SHA1.base64digest(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    header
  end

  # Exec middlewares
  private def middleware_exec(middlewares, clean_room, request, response=nil)
    result = response.nil? ? request : response
    middlewares.each do |middleware|
      if response.nil?
        result = Midori::Sandbox.run(
          clean_room,
          proc { |req| middleware.before(req) },
          result)
      else
        result = Midori::Sandbox.run(
          clean_room,
          proc { |req, resp| middleware.after(req, resp) },
          request,
          result)
      end
      return result if response.nil? && result.is_a?(Midori::Response) # Early stop
    end
    result
  end
end
