defmodule EvercamMedia.Janitor do
  use GenServer
  require Logger
  @vsn DateTime.to_unix(DateTime.utc_now())

  def start_link() do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def init(_args) do
    {:ok, 1}
  end

  def code_change(_old_vsn, state, _extra) do
    Logger.info "Re-init Porcelain"
    ensure_porcelain_is_init()
    {:ok, state}
  end

  defp ensure_porcelain_is_init do
    Porcelain.Init.init()
  end
end
