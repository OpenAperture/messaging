require Logger

defmodule OpenAperture.Messaging.AMQP.RpcHandler do
	use GenServer

	alias OpenAperture.Messaging.RpcRequest
  alias OpenAperture.Messaging.AMQP.ConnectionPool

  @moduledoc """
  This module contains the logic to execute an RPC-style messaging request
  """  

  @doc """
  Specific start_link implementation

  ## Options

  The `api` option represents the ManagerApi to be used for transactions

  The `request` option represents the RpcRequest to be used for transactions

  The `connection_pool` option represents the AMQP.ConnectionPool to be used for transactions

  The `queue` option represents the Messaging.Queue to be used for transactions

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link(pid, RpcRequest.t, pid, OpenAperture.Messaging.Queue.t) :: {:ok, pid} | {:error, String.t} 
  def start_link(api, request, connection_pool, queue) do
    case Agent.start_link(fn -> {:not_started, nil} end) do
      {:ok, response_agent} -> 
        case GenServer.start_link(__MODULE__, %{response_agent: response_agent}) do
          {:ok, pid} -> 
            GenServer.cast(pid, {:execute, api, request, connection_pool, queue})
            {:ok, response_agent}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}    
    end
  end

  @doc """
  Specific start_link implementation

  ## Options

  The `handler` option represents the RpcHandler

  The `timeout` option represents the timeout for an RPC response

  ## Return Values

  {:ok, Response} | {:error, reason}
  """
  @spec get_response(pid, term) :: {:ok, term} | {:error, String.t}
  def get_response(handler, timeout \\ 30) do
    if timeout <= 0 do
      {:error, "An RpcHandler Timeout has occurred"}
    else
      case Agent.get(handler, fn response -> response end) do
        {:completed, response} -> {:ok, response}
        {:error, reason} -> {:error, reason}
        _ ->
          :timer.sleep(1000)
          get_response(handler, timeout-1)
      end
    end
  end

  @doc """
  Callback handler for :execute messages.  This method is responsible for creating an MessagingRpcRequest
  and sending out the request message

  ## Options

  The `api` option represents the ManagerApi to be used for transactions

  The `request` option represents the RpcRequest to be used for transactions

  The `connection_pool` option represents the AMQP.ConnectionPool to be used for transactions

  The `queue` option represents the Messaging.Queue to be used for transactions

  ## Return Values

  {:noreply, Map}
  """
  @spec handle_cast({:execute, pid, RpcRequest.t, pid, OpenAperture.Messaging.Queue.t}, Map) :: {:noreply, Map}
  def handle_cast({:execute, api, request, connection_pool, queue}, state) do
    Logger.debug("[Messaging][RpcHandler] Publishing RPC request to connection pool...")

    {status, request} = RpcRequest.save(api, request)
    if status == :ok do
      payload = RpcRequest.to_payload(request)
      case ConnectionPool.publish(connection_pool, queue.exchange, queue, payload) do
        {:error, reason} -> Agent.update(state[:response_agent], fn _ -> {:error, reason} end)
        :ok -> 
          Agent.update(state[:response_agent], fn _ -> {:in_progress, nil} end)
          GenServer.cast(self, {:response_status, api, request})
      end      
    else
      Logger.error("[Messaging][RpcHandler] Failed to save RPC request!")
      Agent.update(state[:response_agent], fn _ -> {:error, "Failed to save RPC request!"} end)
    end

    {:noreply, state}
  end

  @doc """
  Callback handler for :response_status messages.  This method is responsible for verifying when a MessagingRpcRequest
  has been completed.

  ## Options

  The `api` option represents the ManagerApi to be used for transactions

  The `request` option represents the RpcRequest to be used for transactions

  ## Return Values

  {:noreply, Map}
  """
  @spec handle_cast({:response_status, pid, RpcRequest.t, pid}, map) :: {:noreply, map}
  def handle_cast({:response_status, api, request}, state) do
    {completed, updated_request} = RpcRequest.completed?(api, request)
    if completed do
      if updated_request.status == :completed do
        Logger.debug("[Messaging][RpcHandler][#{request.id}] Request has completed successfully")
        Agent.update(state[:response_agent], fn _ -> {:completed, updated_request.response_body} end)
      else
        Logger.error("[Messaging][RpcHandler][#{request.id}] Request has failed:  #{inspect updated_request.status}")
        Agent.update(state[:response_agent], fn _ -> {:error, updated_request.response_body} end)
      end
      RpcRequest.delete(api, request)
    else
      :timer.sleep(1000)
      GenServer.cast(self, {:response_status, api, updated_request})
    end
    {:noreply, state}
  end
end