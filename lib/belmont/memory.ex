defmodule Belmont.Memory do
  @moduledoc """
  Handles reading and writing to memory.
  CPU memory map:
  * :$0000 - ($800)  2KB of work RAM
  * :$0800 - ($800)  Mirror of $000-$7FF
  * :$1000 - ($800)  Mirror of $000-$7FF
  * :$1800 - ($800)  Mirror of $000-$7FF
  * :$2000 - (8)     PPU Ctrl Registers
  * :$2008 - ($1FF8) Mirror of $2000-$2007
  * :$4000 - ($20)   Registers (Mostly APU
  * :$4020 - ($1FDF) Cartridge Expansion ROM
  * :$6000 - ($2000) SRAM
  * :$8000 - ($4000) PRG-ROM
  * :$C000 - ($4000) PRG-ROM
  """

  use Bitwise
  alias Belmont.Hexstr

  @typedoc """
  Defines the memory state struct.
  * :cartridge - Cartridge memory.
  * :ram - The NES has has 2KB of internal RAM.
  * :lower_bank - The lower bank of program rom.
  * :upper_bank - The upper bank of program rom that can be accessed by the MMU
  * :mapper - The module that defines how memory is read to (and written from) the cartridge.
  """
  @type t :: %__MODULE__{
          cartridge: Belmont.Cartridge.t(),
          ram: tuple(),
          lower_bank: integer(),
          upper_bank: integer(),
          mapper: module()
        }

  defstruct cartridge: %Belmont.Cartridge{},
            ram: {},
            lower_bank: 0,
            upper_bank: 0,
            mapper: Belmont.Mapper.NROM

  @doc """
  Creates a new memory manager.
  """
  @spec new(Belmont.Cartridge.t()) :: t()
  def new(cart) do
    ram = for(_ <- 0..2048, into: [], do: 0x00) |> List.to_tuple()
    mapper = Belmont.Mapper.NROM

    %__MODULE__{
      cartridge: cart,
      ram: ram,
      mapper: mapper,
      lower_bank: mapper.initial_lower_bank(cart),
      upper_bank: mapper.initial_upper_bank(cart)
    }
  end

  @doc """
  Read a byte from memory at the given location.
  """
  @spec read_byte(t(), integer()) :: byte()
  def read_byte(memory, location) do
    cond do
      # read from RAM
      location < 0x2000 ->
        elem(memory.ram, rem(location, 0x800))

      location < 0x4000 ->
        raise "read PPU"

      location == 0x4014 ->
        raise "read PPU 2"

      location == 0x4015 ->
        raise "read APU"

      location == 0x4016 ->
        raise "read controller 1"

      location == 0x4017 ->
        raise "read controller 2"

      location < 0x6000 ->
        raise "read IO registers"

      true ->
        memory.mapper.read_byte(memory, location)
    end
  end

  @doc """
  Read a word from memory at the specified location and return it.
  """
  @spec read_word(t(), integer()) :: integer()
  def read_word(memory, location) do
    low_byte = read_byte(memory, location)
    high_byte = read_byte(memory, location + 1)

    high_byte <<< 8 ||| low_byte
  end

  @doc """
  Write a byte to memory at the specified location.
  """
  @spec write_byte(t(), integer(), byte()) :: t()
  def write_byte(memory, location, value) do
    cond do
      location < 0x2000 ->
        ram = put_elem(memory.ram, rem(location, 0x800), value)
        %{memory | ram: ram}

      location >= 0x4000 and location <= 0x4015 ->
        IO.puts("Writing to #{Hexstr.hex(location, 4)} - Unhandled register write")
        memory

      location >= 0x8000 and location <= 0xFFFF ->
        # write to cartridge ROM for bank switches
        memory.mapper.write_byte(memory, location, value)

      true ->
        raise "write to unhandled memory location #{Hexstr.hex(location, 4)} = #{Hexstr.hex(value, 2)}"
    end
  end
end
