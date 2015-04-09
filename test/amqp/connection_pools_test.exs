require Logger

defmodule OpenAperture.Messaging.AMQP.ConnectionPoolsTest do
  use ExUnit.Case, async: false

  alias OpenAperture.Messaging.AMQP.ConnectionPools

  ## =============================
  # get_pool tests

  test "get_pool - provide url" do
    {_result, _pid} = ConnectionPools.create()
    result = ConnectionPools.get_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])

    assert is_pid result
  end

  test "get_pool - retrieve same connection pool" do
    {_result, _pid} = ConnectionPools.create()

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

  test "get_pool via options" do
    {_result, _pid} = ConnectionPools.create()

    url = "#{UUID.uuid1()}"
    result = ConnectionPools.get_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])

    assert is_pid result
  end

  test "get_pool via options - retrieve same connection pool" do
    {_result, _pid} = ConnectionPools.create()

    url = "#{UUID.uuid1()}"
    result = ConnectionPools.get_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])
    assert is_pid result

    result2 = ConnectionPools.get_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])

    assert is_pid result2
    assert result == result2
  end

  test "remove_pool - provide url" do
    {_result, _pid} = ConnectionPools.create()

    result = ConnectionPools.get_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])
    assert is_pid result

    result = ConnectionPools.remove_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])
    assert result == :ok

    result = ConnectionPools.get_pool([
      connection_url: "amqp://#user:password@host/virtual_host"
      ])

    assert is_pid result
  end

  test "remove_pool via options" do
    {_result, _pid} = ConnectionPools.create()

    url = "#{UUID.uuid1()}"
    result = ConnectionPools.get_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])
    assert is_pid result

    result = ConnectionPools.remove_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])
    assert result == :ok    

    result = ConnectionPools.get_pool([
      username: "user",
      password: "pass",
      host: url,
      virtual_host: "vhost"
      ])

    assert is_pid result
  end  
end