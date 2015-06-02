require Logger

defmodule OpenAperture.Messaging.AMQP.SubscriptionHandlerTest do
  use ExUnit.Case, async: false

  alias AMQP.Basic
  alias AMQP.Exchange
  alias AMQP.Queue

  alias OpenAperture.Messaging.AMQP.SubscriptionHandler
  alias OpenAperture.Messaging.RpcRequest

  alias OpenAperture.Messaging.Queue, as: MessagingQueue
  alias OpenAperture.Messaging.AMQP.Exchange, as: MessagingExchange

  setup do
    Application.ensure_started(:logger)
    :ok
  end  

  # =======================================
  # handle_call({:process_request}) tests

  test "handle_call({:process_request}) - process success" do
    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(_payload, _meta) ->
      :ok
    end

    payload = :erlang.term_to_binary("{}")

    state = %{
      channel: "channel", 
      exchange: queue.exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }
    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
    assert result == :ok
    assert returned_state == state
  end  

  test "handle_call({:process_request}) - requeue success" do
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :reject, fn _, _, opts -> 
      assert opts[:requeue] == true
      :ok 
    end)

    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(_payload, _meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    state = %{
      channel: "channel", 
      exchange: queue.exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }
    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
    assert result == :ok
    assert returned_state == state
  after
    :meck.unload(Basic)
  end

  test "handle_call({:process_request}) - requeue failure" do
    queue = %MessagingQueue{
      name: "test_queue", 
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: true
    }

    callback_handler = fn(_payload, _meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    try do
      state = %{
        channel: "channel", 
        exchange: queue.exchange, 
        queue: queue, 
        callback_handler: callback_handler
      }
      {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
      assert true == false
    rescue exception ->
      assert exception != nil
    end
  end  

  test "handle_call({:process_request}) - requeue disabled" do
    queue = %MessagingQueue{
      name: "test_queue", 
      requeue_on_error: false,
      exchange: %MessagingExchange{name: "aws:us-east-1b", options: [:durable]},
      error_queue: "test_queue_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
      binding_options: [routing_key: "test_queue"]
    }

    meta = %{
      delivery_tag: "123abc",
      redelivered: false
    }

    callback_handler = fn(_payload, _meta) ->
      raise "bad news bears"
    end

    payload = :erlang.term_to_binary("{}")

    try do
      state = %{
        channel: "channel", 
        exchange: queue.exchange, 
        queue: queue, 
        callback_handler: callback_handler
      }
      {:reply, result, returned_state} = SubscriptionHandler.handle_call({:process_request, payload, meta}, %{}, state)
      assert true == false
    rescue exception ->
      assert exception != nil
    end
  end

  ## =============================
  # handle_call({:subscribe_sync}) tests   

  test "handle_call({:subscribe_sync}) - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{name: "test_queue"}

    callback_handler = fn(_payload, _meta) ->
      raise "bad news bears"
    end

    state = %{
      channel: "channel", 
      exchange: exchange, 
      queue: queue, 
      callback_handler: callback_handler
    }

    {:reply, result, returned_state} = SubscriptionHandler.handle_call({:subscribe_sync}, %{}, state)
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
  end

  ## =============================
  # deserialize tests   

  test "deserialize - success" do
    assert SubscriptionHandler.deserialize(:erlang.term_to_binary(%{})) == %{}
  end

  test "deserialize - nil" do
    assert SubscriptionHandler.deserialize(:erlang.term_to_binary(nil)) == nil
  end

  ## =============================
  # deserialize tests   

  test "serilalize - success" do
    assert SubscriptionHandler.serilalize(%{}) == :erlang.term_to_binary(%{})
  end

  test "serilalize - nil" do
    assert SubscriptionHandler.serilalize(nil) == :erlang.term_to_binary(nil)
  end

  ## =============================
  # deserialize_payload tests   

  test "deserialize_payload - success" do
    assert SubscriptionHandler.deserialize_payload(:erlang.term_to_binary(%{}), "") == {true, %{}}
  end

  test "deserialize_payload - nil" do
    assert SubscriptionHandler.deserialize_payload(:erlang.term_to_binary(nil), "") == {true, nil}
  end   

  ## =============================
  # process_async_request tests

  test "process_async_request - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta, _async_info) ->
      try do
        Agent.update(test_agent, fn _ -> %{received_message: true} end)
      rescue e ->
        IO.puts("An unexpected error occurred in test 'process_async_request - success':  #{inspect e}")
      end
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler = SubscriptionHandler.subscribe(%{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
      })

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    test_pid = spawn_link fn -> SubscriptionHandler.process_async_request(channel, callback_handler, subscription_handler) end
    send(test_pid, {:basic_deliver, payload, meta})
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == true
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end  

  test "process_async_request - failure" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)
    :meck.expect(Basic, :reject, fn _, _, _ -> :ok end)

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue"
    }

    subscription_handler = SubscriptionHandler.subscribe(%{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
      })

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    test_pid = spawn_link fn -> SubscriptionHandler.process_async_request(channel, callback_handler, subscription_handler) end
    send(test_pid, {:basic_deliver, payload, meta})
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == false
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end 

  test "process_async_request - basic_cancel" do
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.process_async_request("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end
    end
    send(test_pid, {:basic_cancel, %{no_wait: true}})
    :timer.sleep(100)
  end  

  test "process_async_request - basic_cancel_ok" do
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.process_async_request("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end            
    end
    send(test_pid, {:basic_cancel_ok, %{no_wait: true}})
    :timer.sleep(100)
  end 

  ## =============================
  # start_async_handler tests

  test "start_async_handler - basic_consume_ok" do
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      SubscriptionHandler.start_async_handler("channel", callback_handler, %{})            
    end
    send(test_pid, {:basic_consume_ok, %{consumer_tag: "#{UUID.uuid1()}"}})
    :timer.sleep(100)
  end   

  test "start_async_handler - other" do
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    test_pid = spawn_link fn -> 
      try do
        SubscriptionHandler.start_async_handler("channel", callback_handler, %{}) 
      catch :exit, _ -> 
        assert true == true
      end            
    end
    send(test_pid, {:basic_consume_failed, %{}})
    :timer.sleep(100)
  end   

  ## =============================
  # execute_callback_handler tests

  test "execute_callback_handler - async success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta, _async_info) ->
      try do
        Agent.update(test_agent, fn _ -> %{received_message: true} end)
      rescue e ->
        IO.puts("An unexpected error occurred in test 'execute_callback_handler - async success':  #{inspect e}")
      end
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler_options = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }

    subscription_handler = SubscriptionHandler.subscribe(subscription_handler_options)

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    SubscriptionHandler.execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == true
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end 

  test "execute_callback_handler - async success 1" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta) ->
      try do
        Agent.update(test_agent, fn _ -> %{received_message: true} end)
      rescue e ->
        IO.puts("An unexpected error occurred in test 'execute_callback_handler - sync success':  #{inspect e}")
      end
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler_options = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }

    subscription_handler = SubscriptionHandler.subscribe(subscription_handler_options)

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    SubscriptionHandler.execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == true
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  test "execute_callback_handler - async failure" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta, _async_info) ->
      raise "bad news bears"
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler_options = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }

    subscription_handler = SubscriptionHandler.subscribe(subscription_handler_options)

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    SubscriptionHandler.execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
    :timer.sleep(100)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == false
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  test "execute_callback_handler - sync failure" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)


    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    callback_handler = fn(_payload, _meta) ->
      raise "bad news bears"
    end

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler_options = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }

    subscription_handler = SubscriptionHandler.subscribe(subscription_handler_options)

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    try do
      SubscriptionHandler.execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)
      assert nil == "execute_callback_handler should have thrown an exception"
    rescue e ->
      assert e != nil
    end          

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == false
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  test "execute_callback_handler - failure wrong arity" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)
    :meck.expect(Basic, :reject, fn _, _, _ -> :ok end)
    
    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info, _bad_news_bears) ->
      IO.puts("callback_handler should not be called, wrong arity")
    end

    good_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    subscription_handler_options = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: good_callback_handler
    }

    subscription_handler = SubscriptionHandler.subscribe(subscription_handler_options)
    GenServer.call(subscription_handler, {:set_subscription_options, Map.put(subscription_handler_options, :callback_handler, bad_callback_handler)})

    meta = %{
      delivery_tag: "#{UUID.uuid1()}",
      redelivered: false
    }

    payload = SubscriptionHandler.serilalize(%{})

    SubscriptionHandler.execute_callback_handler(subscription_handler_options, subscription_handler, payload, meta)

    opts = Agent.get(test_agent, fn opts -> opts end)
    assert opts[:received_message] == false
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end  

  ## =============================
  # handle_call({:reject}) tests   

  test "handle_call({:reject}) - success" do
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :reject, fn _, _, _ -> :ok end)    

    SubscriptionHandler.handle_call({:reject, "delivery_tag", false}, %{}, %{}) == {:reply, :ok, %{}}
  after
    :meck.unload(Basic)
  end  

  ## =============================
  # handle_call({:acknowledge}) tests   

  test "handle_call({:acknowledge}) - success" do
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :ack, fn _, _ -> :ok end)    

    SubscriptionHandler.handle_call({:acknowledge, "delivery_tag"}, %{}, %{}) == {:reply, :ok, %{}}
  after
    :meck.unload(Basic)
  end

  ## =============================
  # acknowledge_rpc tests   

  test "acknowledge_rpc - success" do
    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :save, fn _,_ -> {:ok, %RpcRequest{}} end)

    :meck.new(GenServer, [:unstick, :passthrough])
    :meck.expect(GenServer, :call, fn _,_ -> :ok end)

    SubscriptionHandler.acknowledge_rpc(nil, "delivery_tag", nil, %RpcRequest{}) == :ok
  after
    :meck.unload(RpcRequest)
    :meck.unload(GenServer)
  end

  test "acknowledge_rpc - failure" do
    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :save, fn _,_ -> {:error, %RpcRequest{}} end)

    :meck.new(GenServer, [:unstick, :passthrough])
    :meck.expect(GenServer, :call, fn _,_ -> :ok end)

    SubscriptionHandler.acknowledge_rpc(nil, "delivery_tag", nil, %RpcRequest{}) == :ok
  after
    :meck.unload(RpcRequest)
    :meck.unload(GenServer)
  end

  ## =============================
  # handle_call({:acknowledge}) tests   

  test "handle_call({:subscribe_async}) - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end

    callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    state = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }
    SubscriptionHandler.handle_call({:subscribe_async,}, %{}, state) == {:reply, :ok, state}
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  ## =============================
  # handle_call({:subscribe_async}) tests   

  test "handle_call({:subscribe_async}) - success 1" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end

    callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    state = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }
    SubscriptionHandler.handle_call({:subscribe_async,}, %{}, state) == {:reply, :ok, state}
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  ## =============================
  # handle_call({:subscribe_sync}) tests   

  test "handle_call({:subscribe_sync}) - success 1" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    :meck.expect(Queue, :subscribe, fn _, _, _ -> {:ok, "consumer_tag"} end)

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end

    callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    state = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }
    SubscriptionHandler.handle_call({:subscribe_sync,}, %{}, state) == {:reply, :ok, state}
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
  end  

  ## =============================
  # handle_call({:set_subscription_options}) tests   

  test "handle_call({:set_subscription_options}) - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)
    
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)    

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end

    callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    state = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }
    subscription_handler = SubscriptionHandler.subscribe(state)
    GenServer.call(subscription_handler, {:set_subscription_options, %{}})

    returned_opts = GenServer.call(subscription_handler, {:get_subscription_options})
    assert returned_opts == %{}
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end

  ## =============================
  # handle_call({:get_subscription_options}) tests   

  test "handle_call({:get_subscription_options}) - success" do
    :meck.new(Exchange, [:passthrough])
    :meck.expect(Exchange, :declare, fn _, _, _, _ -> :ok end)

    :meck.new(Queue, [:passthrough])
    :meck.expect(Queue, :declare, fn _, _, _ -> :ok end)
    :meck.expect(Queue, :bind, fn _, _, _, _ -> :ok end)

    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :consume, fn _, _, _, _ -> {:ok, "consumer_tag"} end)  

    channel = "channel"
    {:ok, test_agent} = Agent.start_link(fn -> %{received_message: false} end)
    bad_callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end

    callback_handler = fn(_payload, _meta, _async_info) ->
      :ok
    end    

    exchange = %MessagingExchange{name: "exchange"}
    queue = %MessagingQueue{
      name: "test_queue",
      requeue_on_error: false
    }

    state = %{
      channel: channel,
      exchange: exchange,
      queue: queue,
      callback_handler: callback_handler
    }
    subscription_handler = SubscriptionHandler.subscribe(state)
    GenServer.call(subscription_handler, {:set_subscription_options, %{}})

    returned_opts = GenServer.call(subscription_handler, {:get_subscription_options})
    assert returned_opts == %{}
  after
    :meck.unload(Exchange)
    :meck.unload(Queue)
    :meck.unload(Basic)
  end  

  ## =============================
  # handle_call({:reject}) tests   

  test "handle_call({:unsubscribe}) - success" do
    :meck.new(Basic, [:passthrough])
    :meck.expect(Basic, :cancel, fn _, _ -> {:ok, "consumer_tag"} end)    

    SubscriptionHandler.handle_call({:unsubscribe}, %{}, %{channel: "channel", consumer_tag: "consumer_tag"}) == {:reply, :ok, %{}}
  after
    :meck.unload(Basic)
  end      
end