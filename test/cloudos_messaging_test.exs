defmodule CloudOS.Messaging.ConsumerTest do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options %CloudOS.Messaging.AMQP.ConnectionOptions{
		username: "username",
		password: "password",
		virtual_host: "vhost",
		host: "host"
	}
	use CloudOS.Messaging
end

defmodule CloudOS.Messaging.Consumer2Test do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options nil
	use CloudOS.Messaging
end


defmodule CloudOS.MessagingTest do
  use ExUnit.Case, async: false

	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionPool
	alias CloudOS.Messaging.AMQP.ConnectionPools
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange 

  alias CloudOS.Messaging.ConsumerTest
  alias CloudOS.Messaging.Consumer2Test

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe attribute options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "subscribe attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == {:error, "bad news bears"}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "subscribe attribute options - invalid connection pool" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.subscribe(queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end 

   test "publish attribute options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	subscribe_result = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "publish attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "publish attribute options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

  	{subscribe_result, reason} = ConsumerTest.publish(queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end

  test "subscribe options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	subscribe_result = Consumer2Test.subscribe(options, queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "subscribe options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :subscribe, fn pool, exchange, queue, callback -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	subscribe_result = Consumer2Test.subscribe(options, queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == {:error, "bad news bears"}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "subscribe options - invalid connection pool" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	{subscribe_result, reason} = Consumer2Test.subscribe(options, queue, fn(payload, _meta) -> :ok end)
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end 

   test "publish options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	subscribe_result = Consumer2Test.publish(options, queue, "all the datas")
  	assert subscribe_result == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "publish options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	{subscribe_result, reason} = Consumer2Test.publish(options, queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "publish options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	{subscribe_result, reason} = Consumer2Test.publish(options, queue, "all the datas")
  	assert subscribe_result == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end

  test "unsubscribe options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :unsubscribe, fn pool, subscription_handler -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	unsubscribe = Consumer2Test.unsubscribe(options, %{})
  	assert unsubscribe == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "unsubscribe options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :unsubscribe, fn pool, subscription_handler -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	unsubscribe = Consumer2Test.unsubscribe(options, %{})
  	assert unsubscribe == {:error, "bad news bears"}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "unsubscribe options - invalid connection pool" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	{unsubscribe, reason} = Consumer2Test.unsubscribe(options, %{})
  	assert unsubscribe == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end   

  test "close_connection options - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)
  	:meck.expect(ConnectionPools, :remove_pool, fn pool -> :ok end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :close, fn pool -> :ok end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	close_connection = Consumer2Test.close_connection(options)
  	assert close_connection == :ok
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end  

  test "close_connection options - failure" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)
  	:meck.expect(ConnectionPools, :remove_pool, fn pool -> :ok end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :close, fn pool -> {:error, "bad news bears"} end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	close_connection = Consumer2Test.close_connection(options)
  	assert close_connection == {:error, "bad news bears"}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
  end

  test "close_connection options - invalid connection pool" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> nil end)

		queue = %Queue{
			name: "test_queue", 
			exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
			error_queue: "test_queue_error",
			options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
			binding_options: [routing_key: "test_queue"]
		}

		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "host"
		}

  	{close_connection, reason} = Consumer2Test.close_connection(options)
  	assert close_connection == :error
  	assert reason != nil
  after
  	:meck.unload(ConnectionPools)
  end  
end
