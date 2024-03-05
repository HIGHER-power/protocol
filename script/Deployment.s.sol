// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/contracts/HIGHERToken.sol";
import "../src/contracts/PreDistribution.sol";

contract DeploymentScript is Script {
    address[] public premiumWhitelist;
    address[] public whitelist;

    function setUp() public {
        premiumWhitelist = _readAddressesFromFile("data/premium-whitelist.txt");
        whitelist = _readAddressesFromFile("data/whitelist.txt");

        _dumpArray("premiumWhitelist", premiumWhitelist);
        _dumpArray("whitelist", whitelist);
    }

    function run() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        HIGHERToken token = new HIGHERToken("Higher Token", "HIGHER");
        new PreDistribution(address(token), premiumWhitelist, whitelist);

        vm.stopBroadcast();
    }

    function _readAddressesFromFile(
        string memory path
    ) internal returns (address[] memory addresses) {
        uint256 lineCount = 0;
        while (true) {
            string memory line = vm.readLine(path);
            if (bytes(line).length == 0) break;
            lineCount++;
        }
        vm.closeFile(path);

        addresses = new address[](lineCount);
        for (uint256 i = 0; i < lineCount; i++) {
            string memory line = vm.readLine(path);
            addresses[i] = vm.parseAddress(line);
        }
    }

    function _dumpArray(
        string memory name,
        address[] memory array
    ) internal view {
        console.log("Dumping array: ", name);
        for (uint256 i = 0; i < array.length; i++) {
            console.log(array[i]);
        }
    }
}
