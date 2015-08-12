#
# == exchange_resolver.ex
#
# This module contains the logic to resolve the appropriate MessagingExchange for a client
#
require Logger

defmodule OpenAperture.Messaging.AMQP.ExchangeResolver do
	use GenServer

  @moduledoc """
  This module contains the logic to resolve the appropriate MessagingExchange for a client
  """  

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.MessagingExchange

  alias OpenAperture.Messaging.AMQP.Exchange, as: AMQPExchange

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    GenServer.start_link(__MODULE__, %{exchanges: %{}}, name: __MODULE__)
  end

  @doc """
  Method to retrieve a MessagingExchange

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `exchange_id` option defines the exchange id to retrieve

  ## Return Values

  Returns the correct AMQPExchange
  """
  @spec get(term, String.t()) :: AMQPExchange.t
  def get(api, exchange_id) do
    GenServer.call(__MODULE__, {:get, api, exchange_id})
  end

  @doc """
  Call handler to retrieve a MessagingExchange

  ## Options

  The `api` option defines the OpenAperture.ManagerApi process

  The `exchange_id` option defines the MessagingExchange identifier

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state
  
  ## Return Values

  {:reply, AMQPExchange.t, state}
  """
  @spec handle_call({:get, pid, String.t}, term, map) :: {:reply, AMQPExchange.t, map}
  def handle_call({:get, api, exchange_id}, _from, state) do
    if cache_stale?(state) do
      state = %{
        retrieval_time: :calendar.universal_time,
        exchanges: %{}
      }
    end

    exchange = if state[:exchanges][exchange_id] != nil do
      state[:exchanges][exchange_id]
    else
      get_exchange(api, exchange_id)
    end

    state = Map.put(state, :exchanges, Map.put(state[:exchanges], exchange_id, exchange))
    {:reply, exchange, state}
  end

  @doc """
  Method to determine if the cached options are stale (i.e. retrieved > 5 minutes prior)

  ## Return Values

  Boolean
  """
  @spec cache_stale?(map) :: boolean
  def cache_stale?(cache) do
    if cache == nil || cache[:retrieval_time] == nil do
      true
    else
      seconds = :calendar.datetime_to_gregorian_seconds(cache[:retrieval_time])
      now_seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
      (now_seconds - seconds) > 300
    end
  end

  @doc """
  Method to retrieve the exchange

  ## Return Values

  AMQPExchange.t
  """
  @spec get_exchange(pid, String.t()) :: AMQPExchange.t
  def get_exchange(api, exchange_id) do
    case MessagingExchange.get_exchange!(api, exchange_id) do
      nil -> %AMQPExchange{}
      exchange ->
        amqp_exchange = AMQPExchange.from_manager_exchange(exchange)
        if exchange["failover_exchange_id"] != nil do
          case MessagingExchange.get_exchange!(ManagerApi.get_api, exchange["failover_exchange_id"]) do
            nil -> amqp_exchange
            failover_exchange -> %{amqp_exchange | 
              failover_name: failover_exchange["name"],
              failover_routing_key: failover_exchange["routing_key"],
              failover_root_exchange_name: failover_exchange["root_exchange_name"],
            }
          end
        else
          amqp_exchange
        end        
    end
  end
end