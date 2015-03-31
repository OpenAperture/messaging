require Logger

defmodule CloudOS.Messaging.AMQP.TestConsumerPub do

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
		case subscribe(@queue, fn(payload, _meta) -> handle_msg(payload, _meta) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def send_message(payload) do
		IO.puts("sending message:  #{inspect payload}")
		publish(@queue, payload)
	end		

	def handle_msg(payload, _meta) do
		try do
			IO.puts("TestConsumer:  received message #{inspect payload}")
		rescue e in _ ->
			IO.puts("Error when reviewing received message:  #{inspect e}")
		end		
	end	
end

defmodule CloudOS.Messaging.AMQP.TestConsumerPub2 do
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

		case subscribe(options, @queue, fn(payload, _meta) -> handle_msg(payload, _meta) end) do
			:ok -> 
				IO.puts("Successfully subsribed to test_queue!")
				:ok
			{:error, reason} -> 
				IO.puts("Failed subsribed to test_queue:  #{inspect reason}!")
				:error
		end
	end

	def send_message(payload) do
		options = %CloudOS.Messaging.AMQP.ConnectionOptions{
			username: Application.get_env(:cloudos_amqp, :username),
			password: Application.get_env(:cloudos_amqp, :password),
			virtual_host: Application.get_env(:cloudos_amqp, :virtual_host),
			host: Application.get_env(:cloudos_amqp, :host)
		}

		IO.puts("sending message:  #{inspect payload}")
		publish(options, @queue, payload)
	end	

	def handle_msg(payload, _meta) do
		try do
			IO.puts("TestConsumer2:  received message #{inspect payload}")
		rescue e in _ ->
			IO.puts("TestConsumer2:  Error when reviewing received message:  #{inspect e}")
		end		
	end	
end


defmodule CloudOS.Messaging.AMQP.PublishTest do
  use ExUnit.Case
  @moduletag :external

  alias CloudOS.Messaging.AMQP.TestConsumerPub
  alias CloudOS.Messaging.AMQP.TestConsumerPub2

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "subscribe" do
  	CloudOS.Messaging.AMQP.ConnectionPools.start_link

		spawn_link fn -> publish_message(0, 99, "first") end
		spawn_link fn -> publish_message(100, 199, "second") end
		spawn_link fn -> publish_message(200, 299, "third") end
		spawn_link fn -> publish_message(300, 399, "fourth") end

  	:timer.sleep(30000)
  end

  def publish_message(cur_idx, max_idx, identifier) do
  	if cur_idx < max_idx do
	  	send_result = TestConsumerPub.send_message("[#{identifier}][attribute]:  hello world #{cur_idx}!")
	  	IO.puts("send_result:  #{inspect send_result}")   	

	  	send_result = TestConsumerPub2.send_message("[#{identifier}][method]:  hello world #{cur_idx}!")
	  	IO.puts("send_result:  #{inspect send_result}")	  	 		
	  	publish_message(cur_idx+1, max_idx, identifier)
	  	:timer.sleep(1000)
  	end
  end
end
