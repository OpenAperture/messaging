require Logger

defmodule OpenAperture.Messaging.AMQP.ConnectionPoolTest do
  use ExUnit.Case, async: false

  alias AMQP.Connection
  alias AMQP.Channel
  alias AMQP.Basic
  alias AMQP.Exchange
  alias AMQP.Queue

  alias OpenAperture.Messaging.AMQP.SubscriptionHandler
  alias OpenAperture.Messaging.AMQP.ConnectionPool
  alias OpenAperture.Messaging.AMQP.ConnectionPools

  alias OpenAperture.Messaging.Queue, as: MessagingQueue
  alias OpenAperture.Messaging.AMQP.Exchange, as: MessagingExchange

  ## =============================
  # start_link tests

  setup do
    Application.ensure_started(:logger)
    :ok
  end

  test "start_link - success" do
    {result, pid} = ConnectionPool.start_link(%{})
    assert result == :ok
    assert is_pid pid
  end

  test "start_link - failure" do
    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :start_link, fn -> {:error, "bad news bears"} end)

    {result, reason} = ConnectionPool.start_link(%{})
    assert result == :error
    assert String.contains?(reason, "bad news bears")
  after
    :meck.unload(GenEvent)
  end

  ## =============================
  # handle_call({:set_connection_options}) tests

  test "handle_call({:set_connection_options}) - no max_connection_cnt" do
    connection_options = %{
    }

    state = %{
    }

    {:reply, result_connection_options, result_state} = ConnectionPool.handle_call({:set_connection_options, connection_options}, %{}, state)
    assert result_connection_options == connection_options
    assert result_state != nil
    assert result_state[:connection_options] == connection_options
    assert result_state[:max_connection_cnt] == 1
  end

  test "handle_call({:set_connection_options}) - max_connection_cnt = -1" do
    connection_options = %{
      max_connection_cnt: -1
    }

    state = %{
    }

    {:reply, result_connection_options, result_state} = ConnectionPool.handle_call({:set_connection_options, connection_options}, %{}, state)
    assert result_connection_options == connection_options
    assert result_state != nil
    assert result_state[:connection_options] == connection_options
    assert result_state[:max_connection_cnt] == -1
  end

  ## =============================
  # handle_call({:publish}) tests

  test "handle_call({:publish}) - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :publish, fn _, _, _, _, _ -> :ok end)
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:publish, exchange, queue, payload}, %{}, state)
    assert result == :ok
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Basic)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end  

  test "handle_call({:publish}) - fail, invalid channel" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:publish, exchange, queue, payload}, %{}, state)
    assert elem(result, 0) == :error
    assert elem(result, 1) != nil
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:publish}) - fail, invalid connection" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:publish, exchange, queue, payload}, %{}, state)
    assert elem(result, 0) == :error
    assert elem(result, 1) != nil
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end    

  ## =============================
  # handle_call({:subscribe}) tests

  test "handle_call({:subscribe}) - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, {result, subscription_handler}, result_state} = ConnectionPool.handle_call({:subscribe, exchange, queue, fn (_payload, _meta) -> :ok end}, %{}, state)
    assert result == :ok
    assert subscription_handler != nil
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:subscribe}) - fails; channel fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:subscribe, exchange, queue, fn (_payload, _meta) -> :ok end}, %{}, state)
    assert elem(result, 0) == :error
    assert elem(result, 1) != nil
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:subscribe}) - fails; connection fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:subscribe, exchange, queue, fn (_payload, _meta) -> :ok end}, %{}, state)
    assert elem(result, 0) == :error
    assert elem(result, 1) != nil
    assert result_state != nil
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end    

  ## =============================
  # handle_call({:unsubscribe}) tests

  test "handle_call({:unsubscribe}) - success" do
    :meck.new(SubscriptionHandler, [:passthrough])
    {:ok, subscription_handler} = Agent.start_link(fn -> %{} end)
    :meck.expect(SubscriptionHandler, :unsubscribe, fn _ -> :ok end)
    :meck.expect(SubscriptionHandler, :get_subscription_options, fn _ -> %{channel_id: "123abc"}end)

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{
        "123abc" => [subscription_handler]
        },
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {:reply, result, result_state} = ConnectionPool.handle_call({:unsubscribe, subscription_handler}, %{}, state)
    assert result == :ok
    assert subscription_handler != nil
    assert result_state != nil
    assert result_state[:channels_info][:queues_for_channel]["123abc"] == []
  after
    :meck.unload(SubscriptionHandler)
  end

  ## =============================
  # handle_info({:DOWN}) tests

  test "handle_call({:DOWN}) - successfully restart connection, no channels" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, conn, "manually stopped"}, resolved_state)
    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))    
    
    assert original_dict_url == updated_dict_url
    assert original_dict_ref != updated_dict_ref
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:DOWN}) - successfully restart connection, connection fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url,
        retry_cnt: 1
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, conn, "manually stopped"}, resolved_state)
    assert result_state != nil
    assert HashDict.size(result_state[:connections_info][:refs]) == 0
    assert result_state[:channels_info][:channel_connections][connection_url] == nil
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end 

  test "handle_call({:DOWN}) - successfully restart connection, channel fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url,
        retry_cnt: 1
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, conn, "manually stopped"}, resolved_state)
    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))    
    
    assert original_dict_url == updated_dict_url
    assert original_dict_ref != updated_dict_ref

    assert length(result_state[:connections_info][:channels_for_connections][connection_url]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:DOWN}) - successfully restart connection, with channels" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, conn, "manually stopped"}, resolved_state)

    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))  
    
    assert original_dict_url == updated_dict_url
    assert original_dict_ref != updated_dict_ref

    assert result_state[:connections_info][:channels_for_connections][connection_url] != nil
    assert length(result_state[:connections_info][:channels_for_connections][connection_url]) == 1
    new_channel_id_for_connection = List.first(result_state[:connections_info][:channels_for_connections][connection_url])
    assert new_channel_id_for_connection == original_channel_id_for_connection
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end  

  test "handle_call({:DOWN}) - successfully restart channel" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Channel{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)    

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    {original_channel_id_for_connection, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_dict_ref = List.first(HashDict.keys(resolved_state[:channels_info][:refs]))
    assert original_dict_ref != nil
    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, chan, "manually stopped"}, resolved_state)
    assert result_state != nil
    assert length(HashDict.keys(result_state[:channels_info][:refs])) == 1
    assert original_dict_ref != List.first(HashDict.keys(result_state[:channels_info][:refs]))
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "handle_call({:DOWN}) - successfully restart connection, with channels and subscribers" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    {resolved_state, _} = ConnectionPool.subscribe_to_queue(resolved_state, channel_id, exchange, queue, fn (_, _) -> :ok end)

    {:noreply, result_state} = ConnectionPool.handle_info({:DOWN, ref, :process, conn, "manually stopped"}, resolved_state)

    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))  
    
    assert original_dict_url == updated_dict_url
    assert original_dict_ref != updated_dict_ref

    assert result_state[:connections_info][:channels_for_connections][connection_url] != nil
    assert length(result_state[:connections_info][:channels_for_connections][connection_url]) == 1
    new_channel_id_for_connection = List.first(result_state[:connections_info][:channels_for_connections][connection_url])
    assert new_channel_id_for_connection == original_channel_id_for_connection

    queues_for_channel = result_state[:channels_info][:queues_for_channel][new_channel_id_for_connection]
    assert queues_for_channel != nil
    assert length(queues_for_channel) == 1

    queue_info = SubscriptionHandler.get_subscription_options(List.first(queues_for_channel))
    assert queue_info != nil
    assert queue_info[:exchange] == exchange
    assert queue_info[:queue] == queue
    assert queue_info[:callback_handler] != nil

  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end    

  ## =============================
  # handle_info({:other}) tests

  test "handle_info({:other}) - success" do
    {:noreply, result_state} = ConnectionPool.handle_info({:other}, %{})
    assert result_state == %{}
  end

  ## =============================
  # restart_connection tests   

  test "restart_connection - successfully restart connection, no channels" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    result_state = ConnectionPool.restart_connection(state, connection_url, 1)
    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))    
    
    assert original_dict_url == updated_dict_url
    assert original_dict_ref != updated_dict_ref
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "restart_connection - successfully restart connection, connection fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url,
        retry_cnt: 1
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    result_state = ConnectionPool.restart_connection(resolved_state, connection_url, 1)
    assert result_state != nil
    assert HashDict.size(result_state[:connections_info][:refs]) == 0
    assert result_state[:channels_info][:channel_connections][connection_url] == nil
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end 

  test "restart_connection - successfully restart connection, channel fails" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url,
        retry_cnt: 1
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)

    result_state = ConnectionPool.restart_connection(resolved_state, connection_url, 1)
    assert result_state != nil

    assert length(result_state[:connections_info][:channels_for_connections][connection_url]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  test "restart_connection - successfully restart connection, with channels" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    result_state = ConnectionPool.restart_connection(resolved_state, connection_url, 1)

    assert result_state != nil
    updated_dict_url = List.first(HashDict.values(result_state[:connections_info][:refs]))
    updated_dict_ref = List.first(HashDict.keys(result_state[:connections_info][:refs]))  
    
    assert result_state[:connections_info][:channels_for_connections][connection_url] != nil
    assert length(result_state[:connections_info][:channels_for_connections][connection_url]) == 1
    new_channel_id_for_connection = List.first(result_state[:connections_info][:channels_for_connections][connection_url])
    assert new_channel_id_for_connection == original_channel_id_for_connection
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end  

  ## =============================
  # restart_channel tests   

  test "restart_channel - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Channel{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    {original_channel_id_for_connection, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_dict_ref = List.first(HashDict.keys(resolved_state[:channels_info][:refs]))
    assert original_dict_ref != nil
    {result_state, {:ok, channel_id}} = ConnectionPool.restart_channel(resolved_state, connection_url, original_channel_id_for_connection, 1)
    assert result_state != nil
    assert length(HashDict.keys(result_state[:channels_info][:refs])) == 1
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  ## =============================
  # subscribe_to_queue tests   

  test "subscribe_to_queue - successfully restart connection, with channels and subscribers" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    {result_state, _} = ConnectionPool.subscribe_to_queue(resolved_state, original_channel_id_for_connection, exchange, queue, fn (_, _) -> :ok end)

    queues_for_channel = result_state[:channels_info][:queues_for_channel][original_channel_id_for_connection]
    assert queues_for_channel != nil
    assert length(queues_for_channel) == 1

    queue_info = SubscriptionHandler.get_subscription_options(List.first(queues_for_channel))
    assert queue_info != nil
    assert queue_info[:exchange] == exchange
    assert queue_info[:queue] == queue
    assert queue_info[:callback_handler] != nil

  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end    

  ## =============================
  # get_channel tests

  test "get_channel - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :publish, fn _, _, _, _, _ -> :ok end)
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {channel_id, result_state} = ConnectionPool.get_channel(state)
    assert channel_id != nil
    assert result_state != nil
    assert length(HashDict.keys(result_state[:channels_info][:refs])) == 1
    assert Map.size(result_state[:channels_info][:channels]) == 1
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Basic)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  test "get_channel - failed" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {channel_id, result_state} = ConnectionPool.get_channel(state)
    assert channel_id == nil
    assert result_state != nil
    assert HashDict.size(result_state[:channels_info][:refs]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  ## =============================
  # get_connection tests

  test "get_connection - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {channel_id, result_state} = ConnectionPool.get_connection(state)
    assert channel_id != nil
    assert result_state != nil
    assert length(HashDict.keys(result_state[:connections_info][:refs])) == 1
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  test "get_connection - failed" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {channel_id, result_state} = ConnectionPool.get_connection(state)
    assert channel_id == nil
    assert result_state != nil
    assert HashDict.size(result_state[:connections_info][:refs]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  ## =============================
  # create_connections tests

  test "create_connections - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    result_state = ConnectionPool.create_connections(1, state[:connection_options], state)
    assert result_state != nil
    assert length(HashDict.keys(result_state[:connections_info][:refs])) == 1
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  test "create_connections - failed" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    result_state = ConnectionPool.create_connections(1, state[:connection_options], state)
    assert result_state != nil
    assert HashDict.size(result_state[:connections_info][:refs]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end



  ## =============================
  # create_connection tests

  test "create_connection - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, result_state} = ConnectionPool.create_connection(state[:connection_options], state)
    assert ref != nil
    assert result_state != nil
    assert length(HashDict.keys(result_state[:connections_info][:refs])) == 1
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  test "create_connection - failed" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:error, "bad news bears"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new
    }
    state = %{
      connection_options: [
        connection_url: "amqp:rabbithost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, result_state} = ConnectionPool.create_connection(state[:connection_options], state)
    assert ref == nil
    assert result_state != nil
    assert HashDict.size(result_state[:connections_info][:refs]) == 0
  after
    :meck.unload(Connection)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
  end

  # =============================
  # failover_connection tests

  test "failover_connection - no options does not alter state" do
    state = %{}
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state == state
  end

  test "failover_connection - empty options does not alter state" do
    state = %{
      connection_options: %{}
    }
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state == state
  end

  test "failover_connection - already in failover state" do
    state = %{
      failover_connection_pool: %{}
    }
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state == state
  end

  test "failover_connection - create a new connection, no migration of subscribers" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    state = %{
      connection_options: %{
        failover_username: "user",
        failover_password: "pass",
        failover_host: "host",
        failover_virtual_host: "vhost"
      }
    }
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state[:failover_connection_pool] != nil
  after
    :meck.unload(ConnectionPools)
  end
  
  test "failover_connection - create a new connection, migration of subscribers" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:ok, "consumer_tag"} end)

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{
        "123abc": %{
          exchange: %{},
          queue: %{},
          callback_handler: %{}
        }
        },
      refs: HashDict.new      
    }
    state = %{
      connection_options: %{
        failover_username: "user",
        failover_password: "pass",
        failover_host: "host",
        failover_virtual_host: "vhost"
      },
      channels_info: channels_info
    }
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state[:failover_connection_pool] != nil
  after
    :meck.unload(ConnectionPools)
    :meck.unload(ConnectionPool)
  end  

  test "failover_connection - create a new connection, migration has error" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:error, "bad news bears"} end)

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{
        "123abc": %{
          exchange: %{},
          queue: %{},
          callback_handler: %{}
        }
        },
      refs: HashDict.new      
    }
    state = %{
      connection_options: %{
        failover_username: "user",
        failover_password: "pass",
        failover_host: "host",
        failover_virtual_host: "vhost"
      },
      channels_info: channels_info
    }
    old_connection_url = ""

    returned_state = ConnectionPool.failover_connection(state, old_connection_url)
    assert returned_state[:failover_connection_pool] != nil
  after
    :meck.unload(ConnectionPools)
    :meck.unload(ConnectionPool)
  end

  test "restart_channel - flip to failover" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:ok, "consumer_tag"} end)

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url,
        failover_username: "user",
        failover_password: "pass",
        failover_host: "host",
        failover_virtual_host: "vhost"
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    result_state = ConnectionPool.restart_connection(state, connection_url, 0)
    assert result_state != nil
    assert result_state[:failover_connection_pool] != nil
  after
    :meck.unload(ConnectionPools)
    :meck.unload(ConnectionPool)
  end  

  ## =============================
  # handle_info({:DOWN}) tests   

  test "handle_info({:DOWN}) - successfully restart connection, with channels and subscribers" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)    

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    {result_state, _} = ConnectionPool.subscribe_to_queue(resolved_state, original_channel_id_for_connection, exchange, queue, fn (_, _) -> :ok end)

    queues_for_channel = result_state[:channels_info][:queues_for_channel][original_channel_id_for_connection]
    assert queues_for_channel != nil
    assert length(queues_for_channel) == 1

    queue_info = SubscriptionHandler.get_subscription_options(List.first(queues_for_channel))
    assert queue_info != nil
    assert queue_info[:exchange] == exchange
    assert queue_info[:queue] == queue
    assert queue_info[:callback_handler] != nil

  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end

  ## =============================
  # handle_call({:close}) tests   

  test "handle_call({:close}) - success" do
    :meck.new(Connection, [:passthrough])
    {:ok, conn} = Agent.start_link(fn -> %{} end)
    :meck.expect(Connection, :open, fn _ -> {:ok, %Connection{pid: conn}} end)
    :meck.expect(Connection, :close, fn _ -> :ok end)

    {:ok, chan} = Agent.start_link(fn -> %{} end)
    :meck.new(Channel, [:passthrough])
    :meck.expect(Channel, :open, fn _ -> {:ok, %Connection{pid: chan}} end)
    :meck.expect(Channel, :close, fn _ -> :ok end)

    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(GenEvent, [:unstick])
    :meck.expect(GenEvent, :start_link, fn -> {:ok, %{}} end)
    :meck.expect(GenEvent, :sync_notify, fn _, _ -> :ok end)
    :meck.expect(GenEvent, :notify, fn _, _ -> :ok end)

    :meck.new(Logger, [:passthrough])
    :meck.expect(Logger, :log, fn _, _, _ -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :cancel, fn _, _ -> :ok end)
    :meck.expect(Basic, :qos, fn _, _ -> :ok end)

    connections_info = %{
      connections: %{},
      channels_for_connections: %{},
      refs: HashDict.new
    }

    channels_info = %{
      channels: %{},
      channel_connections: %{},
      queues_for_channel: %{},
      refs: HashDict.new      
    }
    connection_url = "amqp:rabbithost"
    state = %{
      connection_options: [
        host: "rabbithost",
        connection_url: connection_url
        ],
      max_connection_cnt: 1,
      connections_info: connections_info, 
      channels_info: channels_info      
    }

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}
    payload = %{
      test: "data"
    }

    {ref, resolved_state} = ConnectionPool.create_connection(state[:connection_options], state)
    original_dict_url = List.first(HashDict.values(resolved_state[:connections_info][:refs]))
    original_dict_ref = List.first(HashDict.keys(resolved_state[:connections_info][:refs]))

    {channel_id, resolved_state} = ConnectionPool.create_channel_for_connection(resolved_state, connection_url)
    original_channel_id_for_connection = List.first(resolved_state[:connections_info][:channels_for_connections][connection_url])
    assert original_channel_id_for_connection == channel_id

    {result_state, _} = ConnectionPool.subscribe_to_queue(resolved_state, original_channel_id_for_connection, exchange, queue, fn (_, _) -> :ok end)

    queues_for_channel = result_state[:channels_info][:queues_for_channel][original_channel_id_for_connection]
    assert queues_for_channel != nil
    assert length(queues_for_channel) == 1

    queue_info = SubscriptionHandler.get_subscription_options(List.first(queues_for_channel))
    assert queue_info != nil
    assert queue_info[:exchange] == exchange
    assert queue_info[:queue] == queue
    assert queue_info[:callback_handler] != nil

    {:reply, :ok, closed_state} = ConnectionPool.handle_call({:close}, %{}, result_state)
    assert closed_state != nil
    assert closed_state[:events] != nil
    assert closed_state[:max_connection_cnt] == 1

    assert closed_state[:connections_info] != nil
    assert closed_state[:connections_info][:connections] == %{}
    assert closed_state[:connections_info][:channels_for_connections] == %{}
    assert closed_state[:connections_info][:refs] == HashDict.new

    assert closed_state[:channels_info] != nil
    assert closed_state[:channels_info][:channels] == %{}
    assert closed_state[:channels_info][:channel_connections] == %{}
    assert closed_state[:channels_info][:queues_for_channel] == %{}
    assert closed_state[:channels_info][:refs] == HashDict.new

  after
    :meck.unload(Connection)
    :meck.unload(Channel)
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(GenEvent)
    :meck.unload(Logger)
    :meck.unload(Basic)
  end
end