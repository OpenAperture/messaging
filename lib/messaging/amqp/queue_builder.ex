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
  alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

  @doc """
  Method to build a populated OpenAperture.Messaging.Queue

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `queue_name` options value provides the name of the Queue

  The `exchange_id` option defines the exchange id to retrieve  

  The `options` option deinfes additional Queue options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec build(pid, String.t(), String.t(), List, String.t()) :: OpenAperture.Messaging.Queue.t
  def build(api, queue_name, exchange_id, options \\ [], binding_options \\ nil) do
    build_with_exchange(queue_name, ExchangeResolver.get(api, exchange_id), options, binding_options)
  end

  @spec build_with_exchange(String.t(), AMQPExchange.t, List, String.t()) :: OpenAperture.Messaging.Queue.t
  def build_with_exchange(queue_name, exchange, options \\ [], binding_options \\ nil) do
    binding_options = case binding_options do
      nil -> [routing_key: queue_name]
      _   -> binding_options
    end
    options_default = [
      durable: true, 
      arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "#{queue_name}_error"}]
    ]

    %Queue{
      name: queue_name, 
      exchange: exchange,
      error_queue: "#{queue_name}_error",
      options: Keyword.merge(options_default, options),
      binding_options: binding_options
    }
  end
end