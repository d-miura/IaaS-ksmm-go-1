require 'path_manager'
require 'slice'
require 'slice_exceptions'
require 'slice_extensions'

# L2 routing switch with virtual slicing.
class PathInSliceManager < PathManager
  def start
    super
    logger.info "#{name} started."
  end

  # rubocop:disable MethodLength
  def packet_in(_dpid, packet_in)
    #puts "packet_in_slice_manager!!"
    return unless packet_in.data.is_a? Parser::IPv4Packet
    #puts packet_in.source_ip_address.to_a[0].class
    return unless packet_in.source_ip_address.to_a[0] == 192
    return if packet_in.destination_ip_address.to_a[0] == 224
    return if packet_in.destination_ip_address.to_a[0] == 172
    return if (packet_in.source_ip_address.to_a[3] > 100 && packet_in.destination_ip_address.to_a[3] > 100)
    return if (packet_in.source_ip_address.to_s == "192.168.10.10" && packet_in.destination_ip_address.to_a[3] > 100)
    return if (packet_in.source_ip_address.to_a[3] > 100 && packet_in.destination_ip_address.to_s == "192.168.10.10")
    puts "packet_in in path_in_slice_manager"
    puts "dpid : #{packet_in.dpid}"
    puts "in_port : #{packet_in.in_port}"
    puts "source_mac : #{packet_in.source_mac}"
    puts "destination_mac : #{packet_in.destination_mac}"
    puts "source_ip_address : #{packet_in.source_ip_address.to_s}"
    puts "destination_ip_address : #{packet_in.destination_ip_address.to_s}"
    puts "@graph length is #{@graph.get_length}"
    puts "@missing_graph length is #{@missing_graph.get_length}"
    #puts packet_in.source_ip_address.to_s
    #puts packet_in.source_ip_address.to_s == "192.168.0.1"
    #サーバのIPを見かけたら、macアドレスを保存しておく
    if packet_in.source_ip_address.to_s == "192.168.10.10" then
      @server_mac = packet_in.source_mac
      puts "--Server mac saved!!--"
    end
    slice = Slice.find do |each|
      #同じスライスに属しているかを判定
      #puts each.member?(packet_in.slice_source)
      #puts each.member?(packet_in.slice_destination(@graph))
      if packet_in.destination_ip_address.to_a[3] < 100 then
        puts "less 100"
        puts each.member?(packet_in.slice_source)
        puts each.member?(packet_in.slice_destination(@graph))
        each.member?(packet_in.slice_source) &&
          each.member?(packet_in.slice_destination(@graph))
      else
        puts "more 100"
        dest_mac = nil
        if @server_mac.nil? then 
          dest_mac = Mac.new("00:00:00:00:00:01")
        else
          dest_mac = @server_mac
        end
        each.member?(packet_in.slice_source) &&
          each.member?(packet_in.slice_destination_vm(@graph,dest_mac))
      end
    end
    puts slice
    ports = if slice
              puts "slice is true"
              path = maybe_create_shortest_path_in_slice(slice.name, packet_in)
              path ? [path.out_port] : []
            else
              puts "slice if false"
              external_ports(packet_in)
            end
    #puts "--path--"
    #puts ports
    packet_out(packet_in.raw_data, ports)
  end
  # rubocop:enable MethodLength

  private

  def packet_out(raw_data, ports)
    ports.each do |each|
      send_packet_out(each.dpid,
                      raw_data: raw_data,
                      actions: SendOutPort.new(each.port_no))
    end
  end

  def maybe_create_shortest_path_in_slice(slice_name, packet_in)
    puts "slice_name is #{slice_name}(#{slice_name.class})"
    if(slice_name == "slice_a" && @load_table[15] > 20) then
      @load_flag = true
    elsif(slice_name == "slice_b" && @load_table[16] > 20) then
      @load_flag = true
    else
      @load_flag = false
    end
    path = maybe_create_shortest_path(packet_in)
    return unless path
    path.slice = slice_name
    path
  end

  def external_ports(packet_in)
    Slice.all.each_with_object([]) do |each, ports|
      next unless each.member?(packet_in.slice_source)
      ports.concat external_ports_in_slice(each, packet_in.source_mac)
    end
  end

  def external_ports_in_slice(slice, packet_in_mac)
    slice.each_with_object([]) do |(port, macs), result|
      next unless @graph.external_ports.any? { |each| port == each }
      result << port unless macs.include?(packet_in_mac)
    end
  end
end
