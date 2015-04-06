defmodule CloudOS.Messaging.AMQP.ExchangeResolverTest do
  use ExUnit.Case, async: false
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias CloudOS.ManagerAPI
  alias CloudOS.Messaging.AMQP.ExchangeResolver

  alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange

  setup_all _context do
    :meck.new(CloudosAuth.Client, [:passthrough])
    :meck.expect(CloudosAuth.Client, :get_token, fn _, _, _ -> "abc" end)

    on_exit _context, fn ->
      try do
        :meck.unload CloudosAuth.Client
      rescue _ -> IO.puts "" end
    end    
    :ok
  end
  
  # =========================================
  # get_exchange tests

  test "get_exchange - success" do
    use_cassette "get_exchange", custom: true do
      exchange = ExchangeResolver.get_exchange(ManagerAPI.get_api, "1")
      assert exchange != nil
      assert exchange.name == "test exchange"
    end
  end

  test "get_exchange - failure" do
    use_cassette "get_exchange_failure", custom: true do
      exchange = ExchangeResolver.get_exchange(ManagerAPI.get_api, "1")
      assert exchange == %CloudOS.Messaging.AMQP.Exchange{failover_name: nil, name: "", options: [:durable], type: :direct}
    end
  end

  #===============================
  # handle_call({:get}) tests

  test "handle_call({:get}) - success cached" do
    state = %{
      retrieval_time: :calendar.universal_time,
      exchanges: %{
        "1" => %AMQPExchange{name: "", options: [:durable]}
      }
    }

    {:reply, exchange, returned_state} = ExchangeResolver.handle_call({:get, ManagerAPI.get_api, "1"}, %{}, state)

    assert returned_state != nil
    assert returned_state[:exchanges]["1"] != nil
    assert exchange != nil
  end

  #=========================
  # cache_stale? tests

  test "cache_stale? - no time" do
    state = %{}
    assert ExchangeResolver.cache_stale?(state) == true
  end

  test "cache_stale? - expired" do
    seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
    seconds = seconds - 301

    state = %{
      retrieval_time: :calendar.gregorian_seconds_to_datetime(seconds)
    }
    assert ExchangeResolver.cache_stale?(state) == true
  end

  test "cache_stale? - valid" do
    state = %{
      retrieval_time: :calendar.universal_time
    }
    assert ExchangeResolver.cache_stale?(state) == false
  end  
end