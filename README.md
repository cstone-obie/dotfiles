# Desccription

My dotfiles and settings. For more info, see:

- [Dotbot documentation](https://github.com/anishathalye/dotbot)
- [Tutorial](https://www.elliotdenolf.com/blog/bootstrap-your-dotfiles-with-dotbot)

## Usage

```sh
cd dotfiles && ./install
```

## Further configuration

### ZSH

ZSH aliases can be overridden in the `$ZSH_CUSTOM/work_env` directory. This can include things like an `aliases.zsh` and a `functions.zsh` file.

### Git

Run the following to make a local Git config file:

```sh
touch ~/.gitconfig_local
```

Include a user section:

```
[user]
    name = <NAME>
    email = <EMAIL>
```

### Git Town

Set up a branch prefix for convenience:

```sh
git config --global git-town.branch-prefix <PREFIX>/
```
