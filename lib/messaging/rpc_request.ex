require Logger

defmodule OpenAperture.Messaging.RpcRequest do

  @moduledoc """
  This module contains definition for an RPC-style request
  """  

  alias OpenAperture.Messaging.RpcRequest
  alias OpenAperture.ManagerApi.MessagingRpcRequest

	defstruct queue_name: "",
		id: nil,
    status: nil,
		request_body: nil,
		response_body: nil

	@type t :: %__MODULE__{}

  @doc """
  Method to convert a RpcRequest struct into a map

  ## Options

  The `request` option defines the RpcRequest

  ## Return Values

  Map
  """
  @spec to_payload(RpcRequest.t) :: Map
  def to_payload(request) do
    Map.from_struct(request)
  end

  @doc """
  Method to convert a map into a Request struct

  ## Options

  The `payload` option defines the Map containing the request

  ## Return Values

  RpcRequest.t
  """
  @spec from_payload(Map) :: RpcRequest.t
  def from_payload(payload) do
		%RpcRequest{
			id: payload[:id],
      status: payload[:status],
  		request_body: payload[:request_body],
  		response_body: payload[:response_body]
  	}
  end

  @doc """
  Method to create or update the RpcRequest in the Manager

  ## Options

  The `api` option defines the ManagerApi PID that should be used for executing requests

  The `request` option defines the Map containing the request

  ## Return Values

  {:ok, RpcRequest.t} | {:error, RpcRequest.t}
  """
  @spec save(pid, RpcRequest.t) :: {:ok, RpcRequest.t} | {:error, RpcRequest.t}
  def save(api, request) do
    payload = RpcRequest.to_payload(request)
  	if request.id == nil do
      Logger.debug("[RpcRequest] Creating new request...")
  		case MessagingRpcRequest.create_request!(api, payload) do
  			nil ->
  				Logger.error("[RpcRequest] Failed to create RPC request!")
  				{:error, request}
  			id ->
  				{:ok, %{request | id: id}}
  		end
  	else
      Logger.debug("[RpcRequest][#{request.id}] Updating request...")
      case MessagingRpcRequest.get_request!(api, request.id) do
        nil -> 
          Logger.debug("[RpcRequest][#{request.id}] Request no longer exists, update will be discarded.")
          {:ok, request}
        _ ->
    			case MessagingRpcRequest.update_request!(api, request.id, payload) do
      			nil ->
      				Logger.error("[RpcRequest][#{request.id}] Failed to update RPC request!")
      				{:error, request}
      			_ ->
      				{:ok, request}
      		end
      end
  	end
  end

  @doc """
  Method to determine if the RpcRequest has been completed remotely

  ## Options

  The `api` option defines the ManagerApi PID that should be used for executing requests

  The `request` option defines the Map containing the request

  ## Return Values

  {true, RpcRequest.t} | {false, RpcRequest.t}
  """
  @spec completed?(pid, RpcRequest.t) :: {true, RpcRequest.t} | {false, RpcRequest.t}
  def completed?(api, request) do
		response = MessagingRpcRequest.get_request(api, request.id)
    if response.success? do
      Logger.debug("[RpcRequest][#{request.id}] Successfully retrieved the updated RPC request")
      updated_request = response.body
      {String.to_atom(updated_request["status"]) == :completed || String.to_atom(updated_request["status"]) == :error, 
        RpcRequest.from_payload(%{
          id: updated_request["id"],
          request_body: updated_request["request_body"],
          response_body: updated_request["response_body"],
      })}      
    else
			Logger.error("[RpcRequest][#{request.id}] Failed to retrieve RPC request, the server returned a #{inspect response.status}:  #{inspect response.raw_body}")
			{true, request}
    end				
  end

  @doc """
  Method to delete an RpcRequest from the Manager

  ## Options

  The `api` option defines the ManagerApi PID that should be used for executing requests

  The `request` option defines the Map containing the request
  """
  @spec delete(pid, RpcRequest.t) :: term
  def delete(api, request) do
		if MessagingRpcRequest.delete_request!(api, request.id) do
			Logger.debug("[RpcRequest][#{request.id}] Successfully deleted RPC request")
		else
			Logger.error("[RpcRequest][#{request.id}] Failed to retrieve RPC request!")
		end  	
  end
end