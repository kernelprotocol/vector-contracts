import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";

module.exports = {
    gasReporter: {
        enabled: true,
    },

    solidity: {
        compilers: [
            {
                version: "0.7.5",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
            {
                version: "0.8.19",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 1000,
                    },
                },
            },
        ],
    },
    mocha: {
        timeout: 1000000000,
    },
};
