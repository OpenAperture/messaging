require Logger

defmodule OpenAperture.Messaging.AMQP.RpcHandlerTest do
  use ExUnit.Case, async: false

  alias OpenAperture.Messaging.AMQP.RpcHandler
  alias OpenAperture.Messaging.RpcRequest
  alias OpenAperture.Messaging.AMQP.ConnectionPool

  setup do
    Application.ensure_started(:logger)
    :ok
  end  

  #===================================
  # get_response tests

  test "get_response - times out" do
    {:ok, agent} = Agent.start_link(fn -> {:not_started, nil} end)

    {:error, reason} = RpcHandler.get_response(agent, 0)
    assert reason != nil
  end

  test "get_response - :completed" do
    {:ok, agent} = Agent.start_link(fn -> {:completed, %{}} end)

    {:ok, response} = RpcHandler.get_response(agent, 1)
    assert response == %{}
  end

  test "get_response - :error" do
    {:ok, agent} = Agent.start_link(fn -> {:error, "bad news bears"} end)

    {:error, reason} = RpcHandler.get_response(agent, 1)
    assert reason == "bad news bears"
  end

  test "get_response - :in_progress timeout" do
    {:ok, agent} = Agent.start_link(fn -> {:in_progress, nil} end)

    {:error, reason} = RpcHandler.get_response(agent, 1)
    assert reason == "An RpcHandler Timeout has occurred"
  end  

  #===================================
  # handle_cast({:execute}) tests

  test "handle_cast({:execute}) - save fails" do
    request = %RpcRequest{
      request_body: %{},
      response_body: %{}
    }

    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :save, fn _,_ -> {:error, request} end)

    {:ok, agent} = Agent.start_link(fn -> {:not_started, nil} end)

    {:noreply, state} = RpcHandler.handle_cast({:execute, nil, request, nil, nil}, %{response_agent: agent})
    assert state[:response_agent] != nil

    {status, response} = Agent.get(agent, fn response -> response end)    
    assert status == :error
    assert response == "Failed to save RPC request!"
  after
    :meck.unload(RpcRequest)    
  end

  test "handle_cast({:execute}) - publish fails" do
    request = %RpcRequest{
      request_body: %{},
      response_body: %{}
    }

    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :save, fn _,_ -> {:ok, request} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :publish, fn _,_,_,_ -> {:error, "bad news bears"} end)

    {:ok, agent} = Agent.start_link(fn -> {:not_started, nil} end)

    {:noreply, state} = RpcHandler.handle_cast({:execute, nil, request, nil, %OpenAperture.Messaging.Queue{}}, %{response_agent: agent})
    assert state[:response_agent] != nil

    {status, response} = Agent.get(agent, fn response -> response end)    
    assert status == :error
    assert response == "bad news bears"
  after
    :meck.unload(RpcRequest)    
    :meck.unload(ConnectionPool)
  end

  test "handle_cast({:execute}) - request complete" do
    request = %RpcRequest{
      request_body: %{},
      response_body: %{}
    }

    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :save, fn _,_ -> {:ok, request} end)
    :meck.expect(RpcRequest, :completed?, fn _,_ -> {true, request} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :publish, fn _,_,_,_ -> {:error, "bad news bears"} end)

    {:ok, agent} = Agent.start_link(fn -> {:not_started, nil} end)

    {:noreply, state} = RpcHandler.handle_cast({:execute, nil, request, nil, %OpenAperture.Messaging.Queue{}}, %{response_agent: agent})
    assert state[:response_agent] != nil

    {status, response} = Agent.get(agent, fn response -> response end)    
    assert status == :error
    assert response == "bad news bears"
  after
    :meck.unload(RpcRequest)    
    :meck.unload(ConnectionPool)
  end  

  #===================================
  # handle_cast({:execute}) tests

  test "handle_cast({:response_status}) - handle error status" do
    request = %RpcRequest{
      status: :error,
      request_body: %{},
      response_body: %{}
    }

    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :completed?, fn _,_ -> {true, request} end)
    :meck.expect(RpcRequest, :delete, fn _,_ -> :ok end)

    {:ok, agent} = Agent.start_link(fn -> {:not_started, nil} end)

    {:noreply, state} = RpcHandler.handle_cast({:response_status, nil, request}, %{response_agent: agent})
    assert state[:response_agent] != nil

    {status, response} = Agent.get(agent, fn response -> response end)    
    assert status == :error
    assert response == %{}
  after
    :meck.unload(RpcRequest)    
  end

  test "handle_cast({:response_status}) - success" do
    request = %RpcRequest{
      status: :completed,
      request_body: %{},
      response_body: %{}
    }

    :meck.new(RpcRequest, [:passthrough])
    :meck.expect(RpcRequest, :completed?, fn _,_ -> {true, request} end)
    :meck.expect(RpcRequest, :delete, fn _,_ -> :ok end)

    {:ok, agent} = Agent.start_link(fn -> {:completed, nil} end)

    {:noreply, state} = RpcHandler.handle_cast({:response_status, nil, request}, %{response_agent: agent})
    assert state[:response_agent] != nil

    {status, response} = Agent.get(agent, fn response -> response end)    
    assert status == :completed
    assert response == %{}
  after
    :meck.unload(RpcRequest)    
  end  
end