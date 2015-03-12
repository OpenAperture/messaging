#
# == connection_pools.ex
#
# This module contains the GenServer for managing getting ConnectionPools
#
require Logger

#http://elixir-lang.org/getting-started/mix-otp/genevent.html
defmodule CloudOS.Messaging.AMQP.ConnectionPools do
  use GenServer

  alias CloudOS.Messaging.AMQP.ConnectionPool

  @moduledoc """
  This module contains the GenServer for managing getting ConnectionPools
  """  

  ## Consumer Methods

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    create()
  end

  @doc """
  Creation method

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}
  @spec create() :: {:ok, pid} | {:error, String.t()}	
  def create() do
    GenServer.start_link(__MODULE__, %{pools: %{}, connection_options: %{}}, name: __MODULE__)
  end

  @doc """
  Method to create or retrieve a connection pool for a set of connection options

  ## Options

  The `connection_options` option defines the set of connection options for the pool (Keyword list)

  ## Return Values

  pool | {:error, reason}
  """
  @spec get_pool(List) :: term | {:error, String.t()}
  def get_pool(connection_options) do
    GenServer.call(__MODULE__, {:get_pool, connection_options})
  end

  ## Server callbacks

  @doc """
  GenServer callback - invoked to handle call (sync) messages.  Catches {:get_pool, ...} messages;
  this callback will create or retrieve the connection pool

  ## Options

  The `connection_options` option contains the AMQP conection options

  ## Return Values

  {:reply, pool, new_state}
  """  
  @spec handle_call({:get_pool, List}, term, term) :: {:reply, term, term}
  def handle_call({:get_pool, connection_options}, _from, state) do
    connection_url = case Keyword.get(connection_options, :connection_url, nil) do
      nil ->
        #build a url:  amqp://user:pass@host/vhost
        user = Keyword.get(connection_options, :username, "")
        password = Keyword.get(connection_options, :password, "")
        host = Keyword.get(connection_options, :host, "")
        virtual_host = Keyword.get(connection_options, :virtual_host, "")
        "amqp://#{user}:#{password}@#{host}/#{virtual_host}"
      connection_url -> connection_url
    end
    connection_options = Keyword.update(connection_options, :connection_url, connection_url, fn(_) -> connection_url end)

    case state[:pools][connection_url] do
      nil ->
        case start_connection_pool(connection_options, state) do
          {:ok, pool, resolved_state} -> 
            Logger.debug("Successfully started ConnectionPool for #{connection_options[:host]}")
            {:reply, pool, resolved_state}
          {:error, reason, resolved_state} ->
            Logger.error("Failed to restart ConnectionPool for #{connection_options[:host]}: #{inspect reason}")
            {:reply, nil, resolved_state}
        end
      pool -> {:reply, pool, state}
    end    
  end

  @doc """
  Method to create a connection pool for a set of connection options

  ## Options

  The `connection_options` option defines the set of connection options for the pool (Keyword list)

  ## Return Values

  {:ok, pool, state} | {:error, reason, state}
  """
  @spec start_connection_pool(List, term) :: {:ok, term, term} | {:error, String.t(), term}
  def start_connection_pool(connection_options, state) do
    case ConnectionPool.start_link(connection_options) do
      {:ok, pool} -> 
        state = Map.put(state, :pools, Map.put(state[:pools], connection_options[:connection_url], pool))
        state = Map.put(state, :connection_options, Map.put(state[:connection_options], connection_options[:connection_url], connection_options))
        {:ok, pool, state}
      {:error, reason} -> {:error, reason, state}
    end    
  end
end