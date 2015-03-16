# CloudOS.Messaging

This reusable Elixir messaging library provides abstracted methods for interacting with the CloudOS Messaging system.  

Currently this library utlizes an AMQP client as its primary communication mechanism.  However, it add supervision and reconnection logic for Connections and Channels.

## Usage

The messaging component is defined via the "using" macro, and can be included in other modules.  Remember to add the :cloudos_messaging application to your Elixir application or module.

### Methods

There are two methods currently exposed via the macro:

#### Subscribe

```iex
subscribe(connection_options \\ @connection_options, queue, callback_handler)
```

The `subscribe` method allows a consumer to receive messages from the messaging system.  The provides 2/3 arguments, depending on the usage pattern:

* connection_options - CloudOS.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  Defaults to the @connection_options attribute.

* queue - CloudOS.Messaging.Queue struct, containing the queue (and possibly exchange) information

* callback_handler - A 2-argument function, which receives message in the form of (payload, metadata)


#### Publish

```iex
publish(connection_options \\ @connection_options, queue, payload)
```

The `publish` method allows a consumer to push messages into the messaging system.  The provides 2/3 arguments, depending on the usage pattern:

* connection_options - CloudOS.Messaging.ConnectionOptions struct, containing the connection username, password, etc...  Defaults to the @connection_options attribute.

* queue - CloudOS.Messaging.Queue struct, containing the queue (and possibly exchange) information

* payload - The term or primitive you want to publish

## Usage Patterns

There are two patterns for using messaging:

### Static Connection Configuration

The first pattern is to define static connection configuration that will be used in the messaging component:

```iex
defmodule CloudOS.Messaging.AMQP.TestConsumer do

	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	#Note that @connection_options must be declared BEFORE the 'use' statement
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
```

### Dynamic Connection Configuration

The second pattern is to pass connection configuration into the various methods of the messaging component:

```iex
defmodule CloudOS.Messaging.AMQP.TestConsumer2 do
	alias CloudOS.Messaging.Queue
	alias CloudOS.Messaging.ConnectionOptions
	alias CloudOS.Messaging.AMQP.ConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

	#Set @connection_options to nil BEFORE the 'use' statement to avoid the warning
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
			username: "username",
			password: "password",
			virtual_host: "vhost",
			host: "rabbitmqhost"
		}

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
```

## Building & Testing

The normal elixir project setup steps are required:

```iex
mix do deps.get, deps.compile
```

You can then run the tests

```iex
MIX_ENV=test mix test test/
```

If you want to run the RabbitMQ system tests (i.e. hit a live system):

1.  Define a new configuration for the "system" environment (config/system.exs) with the following contents:

```
config :cloudos_amqp,
  username: "user",
  password: "pass",
  virtual_host: "env",
  host: "host.myrabbit.com"

config :logger, :console,
  level: :debug
```

2.  Run the following commands on separate machines, able to access the RabbitMQ server:

```iex
MIX_ENV=system mix test test/external/amqp_publish_test.exs --include external:true

MIX_ENV=system mix test test/external/amqp_subscribe_test.exs --include external:true
```