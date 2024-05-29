defmodule Belmont.CPU.AddressingMode do
  @moduledoc """
  Handles the various addressing modes of the CPU. Also determines per mode if a page boundry
  was crossed so that the extra cycles can be accounted for in the CPU.
  """

  use Bitwise
  alias Belmont.Hexstr
  alias Belmont.Memory

  defstruct address: 0x0000, page_crossed: false, additional_cycles: 0

  # TODO: Some of these need extra wrap-around protection when reading a byte

  @doc """
  Get a memory address using the given addressing mode. Accepted modes are:
  * zero_page
  * zero_page_x
  * zero_page_y
  * absolute
  * absolute_x
  * absolute_y
  * indexed_indirect
  * indirect_indexed
  * immediate
  * implied
  * accumulator
  * relative
  * indirect_with_jmp_bug
  """
  # modes that don't return addresses
  def get_address(:implied, _cpu_state),
    do: %__MODULE__{address: 0, page_crossed: false, additional_cycles: 0}

  def get_address(:accumulator, _cpu_state),
    do: %__MODULE__{address: 0, page_crossed: false, additional_cycles: 0}

  # zero page addresses. The zero page exists at 0x0000-0x00ff so only one byte is needed.
  def get_address(:zero_page, cpu_state), do: zero_page_address(cpu_state, 0)
  def get_address(:zero_page_x, cpu_state), do: zero_page_address(cpu_state, cpu_state.registers.x)
  def get_address(:zero_page_y, cpu_state), do: zero_page_address(cpu_state, cpu_state.registers.y)

  # absolute addresses. Address obtained from the 2 current operands.
  def get_address(:absolute, cpu_state), do: absolute_address(cpu_state, 0)
  def get_address(:absolute_x, cpu_state), do: absolute_address(cpu_state, cpu_state.registers.x)
  def get_address(:absolute_y, cpu_state), do: absolute_address(cpu_state, cpu_state.registers.y)

  # indirect addresses.
  def get_address(:indirect, cpu_state), do: indirect_address(cpu_state, 0)
  def get_address(:indirect_with_jmp_bug, cpu_state), do: indirect_address(cpu_state, 0, true)
  def get_address(:indexed_indirect, cpu_state), do: indexed_indirect_address(cpu_state, cpu_state.registers.x)
  def get_address(:indirect_indexed, cpu_state), do: indirect_indexed_address(cpu_state, cpu_state.registers.y)

  # immediate address
  def get_address(:immediate, cpu_state),
    do: %__MODULE__{address: cpu_state.program_counter + 1, page_crossed: false, additional_cycles: 0}

  # relative address.
  def get_address(:relative, cpu_state) do
    branch_offset = Memory.read_byte(cpu_state.memory, cpu_state.program_counter + 1)

    # since the branch offset needs to be interpreted as a signed byte we treat the values 0x00-0x7f as positive
    # and the values 0x80-0xff as negative.
    address =
      if branch_offset < 0x80 do
        cpu_state.program_counter + 2 + branch_offset
      else
        cpu_state.program_counter + 2 + branch_offset - 0x100
      end

    # page crossed is after the branch offset fetch: http://forum.6502.org/viewtopic.php?f=8&t=6370
    page_crossed = page_crossed?(cpu_state.program_counter + 2, address)
    # TODO: Remove additional cycles?
    %__MODULE__{address: address, page_crossed: page_crossed, additional_cycles: 0}
  end

  # handles zero page addresses
  defp zero_page_address(cpu_state, addend) do
    address = Memory.read_byte(cpu_state.memory, cpu_state.program_counter + 1)
    # simulate byte overflow
    wrapped = rem(address + addend, 256)
    %__MODULE__{address: wrapped, page_crossed: false, additional_cycles: 0}
  end

  defp absolute_address(cpu_state, addend) do
    address = Memory.read_word(cpu_state.memory, cpu_state.program_counter + 1)

    %__MODULE__{
      address: rem(address + addend, 65_536),
      page_crossed: page_crossed?(address, address + addend),
      additional_cycles: 0
    }
  end

  defp indirect_address(cpu_state, addend, jmp_bug \\ false) do
    address = Memory.read_word(cpu_state.memory, cpu_state.program_counter + 1) + addend
    mask = address &&& 0x00FF

    low_byte = Memory.read_byte(cpu_state.memory, address)

    high_byte =
      if jmp_bug && mask == 0xFF do
        Memory.read_byte(cpu_state.memory, address - 0xFF)
      else
        Memory.read_byte(cpu_state.memory, address + 1)
      end

    %__MODULE__{address: high_byte <<< 8 ||| low_byte, page_crossed: false, additional_cycles: 0}
  end

  defp indexed_indirect_address(cpu_state, addend) do
    address = Memory.read_byte(cpu_state.memory, cpu_state.program_counter + 1) + addend &&& 0xFF
    wrapped = rem(address + 1, 256)

    low_byte = Memory.read_byte(cpu_state.memory, address)
    high_byte = Memory.read_byte(cpu_state.memory, wrapped)

    %__MODULE__{address: high_byte <<< 8 ||| low_byte, page_crossed: false, additional_cycles: 0}
  end

  defp indirect_indexed_address(cpu_state, addend) do
    address = Memory.read_byte(cpu_state.memory, cpu_state.program_counter + 1)
    wrapped = rem(address + 1, 256)

    low_byte = Memory.read_byte(cpu_state.memory, address)
    high_byte = Memory.read_byte(cpu_state.memory, wrapped)

    combined_address = high_byte <<< 8 ||| low_byte
    new_address = combined_address + addend &&& 0xFFFF

    page_crossed = page_crossed?(combined_address, new_address)
    %__MODULE__{address: new_address, page_crossed: page_crossed, additional_cycles: 0}
  end

  # determine if a page cross occured between two addresses
  defp page_crossed?(address1, address2) do
    Bitwise.band(address1, 0xFF00) != Bitwise.band(address2, 0xFF00)
  end
end
