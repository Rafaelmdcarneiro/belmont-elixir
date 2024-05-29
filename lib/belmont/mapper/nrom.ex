defmodule Belmont.Mapper.NROM do
  @moduledoc """
  An implementation of the NROM mapper (mapper #0).
  https://wiki.nesdev.com/w/index.php/NROM
  """

  alias Belmont.Mapper

  @behaviour Mapper

  @impl Mapper
  def initial_lower_bank(_cartridge), do: 0

  @impl Mapper
  def initial_upper_bank(cartridge), do: length(cartridge.prg_rom_banks) - 1

  @impl Mapper
  def read_byte(memory, location) do
    if location >= 0xC000 do
      bank_loc = location - 0xC000

      memory.cartridge.prg_rom_banks
      |> Enum.at(memory.upper_bank)
      |> elem(bank_loc)
    else
      bank_loc = location - 0x8000

      memory.cartridge.prg_rom_banks
      |> Enum.at(memory.lower_bank)
      |> elem(bank_loc)
    end
  end

  @impl Mapper
  # The NROM mapper doesn't do any bank switching, so no writes need to be handled.
  def write_byte(memory, _location, _value), do: memory
end
