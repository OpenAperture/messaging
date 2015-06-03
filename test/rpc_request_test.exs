require Logger

defmodule OpenAperture.Messaging.RpcRequestTest do
  use ExUnit.Case, async: false

  alias OpenAperture.Messaging.RpcRequest
  alias OpenAperture.ManagerApi.MessagingRpcRequest
  alias OpenAperture.ManagerApi

  setup do
    Application.ensure_started(:logger)
    :ok
  end  

  test "from_payload" do
    payload = %{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    request = RpcRequest.from_payload(payload)
    assert request != nil
    assert request.id == 123
    assert request.request_body == %{}
    assert request.response_body == %{}

  end

  test "to_payload" do
    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    payload = RpcRequest.to_payload(request)
    assert payload != nil
    assert request.id == payload[:id]
    assert request.request_body == payload[:request_body]
    assert request.response_body == payload[:response_body]
  end   

  #=====================================
  # save tests

  test "save - new request success" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :create_request!, fn _,_ -> 123 end)

    request = %RpcRequest{
      request_body: %{},
      response_body: %{}
    }

    {:ok, returned_request} = RpcRequest.save(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == 123
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "save - new request failed" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :create_request!, fn _,_ -> nil end)

    request = %RpcRequest{
      request_body: %{},
      response_body: %{}
    }

    {:error, returned_request} = RpcRequest.save(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == nil
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "save - existing request success" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :update_request!, fn _,_,_ -> 123 end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    {:ok, returned_request} = RpcRequest.save(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == 123
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "save - existing request failed" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :update_request!, fn _,_,_ -> nil end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    {:error, returned_request} = RpcRequest.save(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == 123
  after
    :meck.unload(MessagingRpcRequest)
  end

  #===================================
  # completed? tests

  test "completed? - success" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :get_request!, fn _,_ -> %{"id" => 123, "status" => "completed"} end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    {true, returned_request} = RpcRequest.completed?(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == 123
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "completed? - success not completed" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :get_request!, fn _,_ -> %{"id" => 123, "status" => "in_progress"} end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    {false, returned_request} = RpcRequest.completed?(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request.id == 123
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "completed? - failed" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :get_request!, fn _,_ -> nil end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    {true, returned_request} = RpcRequest.completed?(ManagerApi.get_api, request)
    assert returned_request != nil
    assert returned_request == request
  after
    :meck.unload(MessagingRpcRequest)
  end  

  #===================================
  # delete tests

  test "delete - success" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :delete_request!, fn _,_ -> true end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    RpcRequest.delete(ManagerApi.get_api, request)
  after
    :meck.unload(MessagingRpcRequest)
  end

  test "delete - failed" do
    :meck.new(MessagingRpcRequest, [:passthrough])
    :meck.expect(MessagingRpcRequest, :delete_request!, fn _,_ -> false end)

    request = %RpcRequest{
      id: 123,
      request_body: %{},
      response_body: %{}
    }

    RpcRequest.delete(ManagerApi.get_api, request)
  after
    :meck.unload(MessagingRpcRequest)
  end   
end