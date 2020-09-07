// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SFarm.sol";


contract TestGauge is SSimplePool, ICurveGauge, ICurveMinter {
    address public reward;
    
	constructor(address _farm, address _underlying, address _reward) SSimplePool(_farm, _underlying) public {
		initialize(msg.sender, _farm, _underlying, _reward);
	}
	
	function initialize(address governor, address _farm, address _underlying, address _reward) public initializer {
	    super.initialize(governor, _farm, _underlying);
	    
	    reward     = _reward;
	    IERC20(reward).totalSupply();           // just check
	}
    
    function deposit(uint _value) override external {
        farming(msg.sender, _value);
    }
    function deposit(uint, address) override external {
        require(false, 'no support deposit(uint, address)');
    }
    function withdraw(uint _value) override external {
        unfarming(msg.sender, _value);
    }
    function withdraw(uint _value, bool claim_rewards) override external {
        claim_rewards;
        unfarming(msg.sender, _value);
    }
    function claim_rewards() override external {
        reward.safeTransfer(msg.sender, 10);
    }
    function claim_rewards(address) override external {
        require(false, 'no support claim_rewards(address)');
    }
    function claimable_reward(address addr) override external view returns (uint) {
        addr;
        return 10;
    }
    function claimable_tokens(address addr) override external view returns (uint) {
        return harvestCapacity(addr)[1];
    }
    function integrate_checkpoint() override external view returns (uint) {
        return now;
    }
    function token() override external view returns (address) {
        return 0xD533a949740bb3306d119CC777fa900bA034cd52;      // CRV
    }
    function mint(address _gauge) override external {
        _gauge;
        harvest();
    }
}


contract TestReward is ERC20 {

	constructor() ERC20("Reward for Test", "Reward") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(msg.sender,  21000000 * 10 ** uint256(decimals));
	}
}


