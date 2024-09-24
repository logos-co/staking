# @logos-co/staking[![Github Actions][gha-badge]][gha] [![Codecov][codecov-badge]][codecov] [![Foundry][foundry-badge]][foundry]

[gha]: https://github.com/logos-co/staking/actions
[gha-badge]: https://github.com/logos-co/staking/actions/workflows/ci.yml/badge.svg
[codecov]: https://codecov.io/gh/logos-co/staking
[codecov-badge]: https://codecov.io/gh/logos-co/staking/graph/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

This project is a smart contract system built for secure token staking and reward management on the Ethereum blockchain. It provides essential components for handling staking operations, managing rewards, and ensuring the security of staked assets. The system is designed to be robust, leveraging mathematical precision for reward calculations and secure vaults for asset protection.

### Key Components

- **StakeManager**: This contract handles the core staking operations. It is responsible for managing the staking process, calculating rewards, and tracking expired staking periods using advanced mathematical calculations. The contract utilizes OpenZeppelin’s ERC20 and math utilities to ensure accuracy and security.
- **StakeVault**: This contract is responsible for securing user stakes. It facilitates the interactions between users and the staking system by ensuring that staked tokens are properly managed. The vault communicates with StakeManager to handle staking and unstaking operations while ensuring the safety of funds.

## Features

- **Secure Staking**: Users can stake tokens securely, with all interactions governed by the StakeVault and managed by StakeManager. StakeVault is actually owned by the user, and is the only account allowed to perform actions on it, where it store the staked tokens. StakeVault recognizes the validity of the StakeVault codehash to allow interacting with it, knowing that the code actually holds the tokens when it should.
- **Reward Estimation**: The system provides accurate reward estimation, using mathematical formulas to calculate earnings based on staking time and amount.
- **Management of Expired Stakes**: StakeManager tracks and manages expired staking periods, allowing for the efficient handling of staking cycles.
- **Integration with ERC20 Tokens**: Built on top of the OpenZeppelin ERC20 token standard, the system ensures compatibility with any ERC20-compliant token.

## Installation

To install the dependencies for this project, run the following command:

```bash
pnpm install
```

## Usage

### Staking Tokens

To stake tokens, the `StakeVault` contract interacts with the `StakeManager`. You can call the `stake` function from StakeVault with the desired amount and duration.

```solidity
function stake(uint256 _amount, uint256 _time) external onlyOwner;
```

### Managing Rewards

Rewards are calculated based on the staking period and amount. `StakeManager` provides functions to manage and track the reward process.

### Security

The system is designed to protect staked tokens and ensure users’ assets remain safe throughout the staking process.

## Development

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

For this script to work, you need to have a `MNEMONIC` environment variable set to a valid
[BIP39 mnemonic](https://iancoleman.io/bip39/).

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting](https://book.getfoundry.sh/tutorials/solidity-scripting.html) tutorial.

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
pnpm gas-report
```

Get a gas snapshot:

```bash
forge snapshot
```

### Lint

Lint the contracts:

```sh
$ pnpm lint
```

### Test

Run the tests:

```sh
$ forge test
```

#### Prepare to commit

Formats, generates snapshot and gas report:

```sh
pnpm run adorno
```

## License

This project is licensed under MIT.
