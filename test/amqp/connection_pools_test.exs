require Logger

defmodule CloudOS.Messaging.AMQP.ConnectionPoolsTest do
  use ExUnit.Case

  alias AMQP.Connection
  alias AMQP.Channel
  alias AMQP.Basic
  alias AMQP.Exchange
  alias AMQP.Queue

  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools

  alias CloudOS.Messaging.Queue, as: MessagingQueue
  alias CloudOS.Messaging.AMQP.Exchange, as: MessagingExchange

  ## =============================
  # start_link tests

  test "start_link - success" do
    {result, pid} = ConnectionPools.start_link()
    assert result == :ok
    assert is_pid pid
  end

  ## =============================
  # start_link tests

  test "create - success" do
    {result, pid} = ConnectionPools.create()
    assert result == :ok
    assert is_pid pid
  end

  ## =============================
  # get_pool tests

  test "get_pool - provide url" do
    {result, pid} = ConnectionPools.create()
    result = ConnectionPools.get_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])

    assert is_pid result
  end

  test "get_pool - retrieve same connection pool" do
    {result, pid} = ConnectionPools.create()

    url = "#{UUID.uuid1()}"
    result = ConnectionPools.get_pool([
      connection_url: url
      ])

    assert is_pid result

    result2 = ConnectionPools.get_pool([
      connection_url: url
      ])

    assert is_pid result2

    assert result == result2
  end

  test "get_pool - fails" do
    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :start_link, fn opts -> {:error, "bad news bears"} end)

    {result, pid} = ConnectionPools.create()
    result = ConnectionPools.get_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])

    assert result == nil
  after
    :meck.unload(ConnectionPool)
  end
end