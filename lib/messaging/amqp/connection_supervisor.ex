#
# == connection_supervisor.ex
#
# This module contains the supervisor for the ConnectionPools
#
require Logger

defmodule OpenAperture.Messaging.AMQP.ConnectionSupervisor do
  use Supervisor

  @moduledoc """
  This module contains the supervisor for the ConnectionPools
  """

  @doc """
  Specific start_link implementation

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: Supervisor.on_start
  def start_link do
    Logger.info("[ConnectionSupervisor] Starting...")
    :supervisor.start_link(__MODULE__, [])
  end

  @doc """
  GenServer callback - invoked when the server is started.

  ## Options

  The `args` option represents the args to the GenServer.

  ## Return Values

      {:ok, state} | {:ok, state, timeout} | :ignore | {:stop, reason}
  """
  @spec init(term) :: {:ok, term} | {:ok, term, term} | :ignore | {:stop, String.t}
  def init([]) do
    import Supervisor.Spec

    children = [
      # Define workers and child supervisors to be supervised
      worker(OpenAperture.Messaging.AMQP.ConnectionPools, []),
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    supervise(children, opts)
  end
end