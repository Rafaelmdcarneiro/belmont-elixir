defmodule Belmont.Mapper do
  @moduledoc """
  Defines a behavior that all mappers should implement
  """

  alias Belmont.Cartridge
  alias Belmont.Memory

  @doc """
  Returns the offset that the lower memory bank should be initially set to.
  """
  @callback initial_lower_bank(Cartridge.t()) :: integer()

  @doc """
  Returns the offset that the upper memory bank should be initially set to.
  """
  @callback initial_upper_bank(Cartridge.t()) :: integer()

  @doc """
  Read a byte from the active memory banks.
  """
  @callback read_byte(Memory.t(), integer()) :: byte()

  @doc """
  Write a byte. Used for bank switching.
  """
  @callback write_byte(Memory.t(), integer(), byte()) :: Memory.t()
end
