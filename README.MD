## Explodelon 💣
A minimal Saturn Bomberman clone that is easy to play on RecalBox with friends. Will also work as a way to add new interesting game mechanics.

### Development setup
For developing and building, the dependencies [Lua](https://www.lua.org/), [LuaRocks](https://luarocks.org/), [Make](https://www.gnu.org/software/make/), Zip, [Teal](https://teal-language.org/), and [Busted](https://lunarmodules.github.io/busted/) are needed.

So, something like ```sudo apt install luarocks make zip``` and then ```sudo luarocks install tl && sudo luarocks install busted``` or similar for your system should do the trick.

You most likely want to setup so that you have a Teal LSP, see [here](https://github.com/teal-language/tl?tab=readme-ov-file#text-editor-support).

### Running the game
First run `make package` which will produce the game file `explodelon.lutro` file. Easiest way to run it is to install [RetroArch](https://www.retroarch.com/?page=platforms).

You can now run the game directly using `./retroarch --verbose -L cores/lutro_libretro.so path/to/explodelon.lutro` (you might need to start it normally first and add the Lutro core first).

> Tip: You can create a .env file and add `LUTRO_DIST_DIR=...` to override where `make package` will put the game.

> Tip: The `--verbose` flag will give you helpful output if the game crashes during development. This is the main reason to use RetroArch over Ludo.

### Recomended core
The game will run using existing compiled and distributed cores. However, some graphis, such as the yellow dino stun cry text, only displays correctly when using a core that supports scaling. To obtain a core with scaling support, it must be built from source. Building from source also allows the core to be compiled with LuaJIT, which gives better performance.

The CI for the fork at https://github.com/efredriksson/libretro-lutro builds from a recent version of `lutro` and archives the built artifacts. CI builds exists for:
 * Windows
 * Windows with LuaJIT
 * Raspberry Pi 4/5 running Recalbox (build_linux_arm64)

This fork also have added support for more joysticks and allows playing the game with 10 players.

Easiest way to get the .so file into your recalbox installation is to [ssh in and remount the volume for write](https://wiki.recalbox.com/en/tutorials/system/access/folders-and-ssh-commands), then you can [scp](https://man7.org/linux/man-pages/man1/scp.1.html) the .so file in (consider renaming existing lutro core as a way to backup).
