#
# == queue_builder.ex
#
# This module contains the logic to build a populated OpenAperture.Messaging.Queue
#
require Logger

defmodule OpenAperture.Messaging.AMQP.QueueBuilder do

  @moduledoc """
  This module contains the logic to build a populated OpenAperture.Messaging.Queue
  """  

	alias OpenAperture.Messaging.Queue
	alias OpenAperture.Messaging.AMQP.ExchangeResolver

  @doc """
  Method to build a populated OpenAperture.Messaging.Queue

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `queue_name` options value provides the name of the Queue

  The `exchange_id` option defines the exchange id to retrieve  

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec build(pid, String.t(), String.t()) :: OpenAperture.Messaging.Queue.t
	def build(api, queue_name, exchange_id) do
		%Queue{
      name: queue_name, 
      exchange: ExchangeResolver.get(api, exchange_id),
      error_queue: "#{queue_name}_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "#{queue_name}_error"}]],
      binding_options: [routing_key: queue_name]
    }
	end
end