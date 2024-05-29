defmodule Belmont do
  @moduledoc """
  Entry point for the emluator
  """

  def main(_args \\ []) do
    {:ok, cart} = Belmont.Cartridge.load_rom("nestest/nestest.nes")

    cart
    |> Belmont.Memory.new()
    |> Belmont.CPU.new()
    |> Map.put(:program_counter, 0xC000)
    |> Belmont.CPU.step()
  end
end
