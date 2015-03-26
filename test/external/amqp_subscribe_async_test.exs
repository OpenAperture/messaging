require Logger

defmodule CloudOS.Messaging.AMQP.TestConsumerAsyncSub do

	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options %CloudOS.Messaging.AMQP.ConnectionOptions{
		username: Application.get_env(:cloudos_amqp, :username),
		password: Application.get_env(:cloudos_amqp, :password),
		virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
		host: Application.get_env(:cloudos_amqp, :host)
	}
	use CloudOS.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

	def subscribe() do
		IO.puts("subscribe")
		case subscribe(@queue, fn(payload, _meta, async_info) -> handle_msg(payload, _meta, async_info) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def handle_msg(payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = async_info) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
			CloudOS.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
			CloudOS.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
		end
	end	
end

defmodule CloudOS.Messaging.AMQP.TestConsumerAsyncSub2 do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	@connection_options nil
	use CloudOS.Messaging

	@queue %Queue{
		name: "test_queue", 
		exchange: %AMQPExchange{name: "aws:us-east-1b", options: [:durable]},
		error_queue: "test_queue_error",
		options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "test_queue_error"}]],
		binding_options: [routing_key: "test_queue"]
	}

	def subscribe() do
		IO.puts("subscribe in TestConsumer2")
		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:cloudos_amqp, :username),
			password: Application.get_env(:cloudos_amqp, :password),
			virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
			host: Application.get_env(:cloudos_amqp, :host)
		}

		case subscribe(options, @queue, fn(payload, _meta, async_info) -> handle_msg(payload, _meta, async_info) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def handle_msg(payload, meta, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = async_info) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
			CloudOS.Messaging.AMQP.SubscriptionHandler.acknowledge(subscription_handler, delivery_tag)
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
			CloudOS.Messaging.AMQP.SubscriptionHandler.reject(subscription_handler, delivery_tag)
		end
	end		
end


defmodule CloudOS.Messaging.AMQP.SubscribeTest do
  use ExUnit.Case
  @moduletag :external

  alias CloudOS.Messaging.AMQP.TestConsumerAsyncSub
  alias CloudOS.Messaging.AMQP.TestConsumerAsyncSub2

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe" do
  	CloudOS.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerAsyncSub.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  

  test "subscribe2" do
  	CloudOS.Messaging.AMQP.ConnectionPools.start_link

  	subscribe_result = TestConsumerAsyncSub2.subscribe()
  	assert subscribe_result == :ok

  	:timer.sleep(30000)
  end  
end
