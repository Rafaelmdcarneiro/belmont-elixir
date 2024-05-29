defmodule Belmont.Cartridge do
  @moduledoc """
  Parses the header from an iNES rom file. According the to iNES spec
  this is where the mapper number, sprite mirroring and game data sizes are
  all stored. See page 28 of http://nesdev.com/NESDoc.pdf for a specification.
  """

  @typedoc """
  * :prg_rom_banks_count - Number of 16 KB program rom banks; The area used to store the program code.
  * :prg_rom_banks - The program data for the game seperated in 16KB chunks.
  * :chr_rom_banks_count - Number of 8 KB character rom banks; The area used to store game graphics.
  * :chr_rom_banks - The graphics data for the game seperated in 8KB chunks.
  * :prg_ram_banks_count - Number of 8 KB RAM banks. 1 page of RAM is assumed if the header says 0.
  * :mapper - Number of mapper used to switch addressable memory within the cartridge.
  * :mirroring_mode - The game's mirroring mode. See https://wiki.nesdev.com/w/index.php/Mirroring for details on mirroring.
  * :battery_backed_ram - The game uses battery backed persistent memory.
  * :trainer_present - The rom contains a trainer. We don't use this data, but need to know to read past it.
  """
  @type t :: %__MODULE__{
          prg_rom_banks_count: integer(),
          prg_rom_banks: [tuple()],
          chr_rom_banks_count: integer(),
          chr_rom_banks: [tuple()],
          prg_ram_banks_count: integer(),
          mapper: integer(),
          mirroring_mode: :horizontal | :vertical | :four_screen,
          battery_backed_ram: boolean(),
          trainer_present: boolean()
        }

  defstruct prg_rom_banks_count: 0,
            prg_rom_banks: [{}],
            chr_rom_banks_count: 0,
            chr_rom_banks: [{}],
            prg_ram_banks_count: 0,
            mapper: 0,
            mirroring_mode: :horizontal,
            battery_backed_ram: false,
            trainer_present: false

  @doc """
  Loads the rom file at the given path
  """
  @spec load_rom(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_rom(rom_file_path) do
    case File.read(rom_file_path) do
      {:ok, file_contents} -> parse_rom_contents(file_contents)
      err -> err
    end
  end

  @doc """
  Parses the contents of an already loaded ROM
  """
  @spec parse_rom_contents(binary()) :: {:ok, t()} | {:error, String.t()}
  def parse_rom_contents(rom) do
    with {:ok, cart} <- parse_header(rom),
         {:ok, cart_with_game_data} <- parse_game_data(cart, rom) do
      {:ok, cart_with_game_data}
    else
      err -> err
    end
  end

  @doc """
  Like parse_rom_contents/1, but raises an error.
  """
  @spec parse_rom_contents!(binary()) :: t()
  def parse_rom_contents!(rom) do
    case parse_rom_contents(rom) do
      {:ok, cart} -> cart
      {:error, reason} -> raise "Unable to parse rom contents: #{reason}"
    end
  end

  # parse out the header of the rom and place it in the struct. We need some of that data to successfully read
  # the game data from the rom
  @spec parse_header(binary()) :: {:ok, t()} | {:error, String.t()}
  defp parse_header(rom) do
    try do
      <<0x4E, 0x45, 0x53, 0x1A, prg_rom_banks::8, chr_rom_banks::8, lower_mapper::4, four_screen_mirroring::1,
        trainer_present::1, battery_backed_ram::1, mirroring::1, upper_mapper::4, _unused_flags::4, prg_ram_banks::8,
        _rest::binary>> = rom

      # get the mapper number
      <<mapper>> = <<upper_mapper::4, lower_mapper::4>>

      # get the mirroring mode
      mirroring_mode =
        case {mirroring, four_screen_mirroring} do
          {0, 0} -> :horizontal
          {1, 0} -> :vertical
          {_, 1} -> :four_screen
        end

      # assume 1 bank if the header says 0
      prg_ram_banks = if prg_ram_banks == 0, do: 1, else: prg_ram_banks

      {:ok,
       %__MODULE__{
         prg_rom_banks_count: prg_rom_banks,
         chr_rom_banks_count: chr_rom_banks,
         prg_ram_banks_count: prg_ram_banks,
         mapper: mapper,
         mirroring_mode: mirroring_mode,
         battery_backed_ram: battery_backed_ram == 1,
         trainer_present: trainer_present == 1
       }}
    rescue
      MatchError -> {:error, "Unable to parse the ROM header"}
    end
  end

  # parse the game data out of the rom and place it in the given cart struct
  @spec parse_game_data(t(), binary()) :: {:ok, t()} | {:error, String.t()}
  defp parse_game_data(cart, rom) do
    trainer_data_size = if cart.trainer_present, do: 512 * 8, else: 0
    prg_data_size = cart.prg_rom_banks_count * 16_384 * 8
    chr_data_size = cart.chr_rom_banks_count * 8_192 * 8

    try do
      <<_header::bitstring-size(128), _trainer::bitstring-size(trainer_data_size),
        prg_data::bitstring-size(prg_data_size), chr_data::bitstring-size(chr_data_size)>> = rom

      prg_rom_banks = chunk_binary(prg_data, 16_384)
      chr_rom_banks = chunk_binary(chr_data, 8_192)

      {:ok, %{cart | prg_rom_banks: prg_rom_banks, chr_rom_banks: chr_rom_banks}}
    rescue
      MatchError -> {:error, "Unable to parse the game data of the rom file"}
    end
  end

  defp chunk_binary(binary, chunk_size) do
    binary
    |> :binary.bin_to_list()
    |> Enum.chunk_every(chunk_size, chunk_size, [])
    |> Enum.map(&List.to_tuple/1)
  end
end
