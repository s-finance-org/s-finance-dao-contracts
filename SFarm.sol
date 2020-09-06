// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
//pragma experimental ABIEncoderV2;

import "./SToken.sol";
import "./Governable.sol";

interface IFarm {
    function crop() external view returns (address);
}

interface ISPool {
    event Farming(address indexed farmer, address indexed from, uint amount);
    event Unfarming(address indexed farmer, address indexed to, uint amount);
    event Harvest(address indexed farmer, address indexed to, uint[] amounts);
    
    function setHarvestSpan(uint _span, bool isLinear) external;
    function farming(uint amount) external;
    function farming(address from, uint amount) external;
    function unfarming() external returns (uint amount);
    function unfarming(uint amount) external returns (uint);
    function unfarming(address to, uint amount) external returns (uint);
    function harvest() external returns (uint[] memory amounts);
    function harvest(address to) external returns (uint[] memory amounts);
    function harvestCapacity(address farmer) external view returns (uint[] memory amounts);
}

contract SStakingPool is ISPool, Governable {
    using SafeMath for uint;
    using TransferHelper for address;

	address public farm;
	address public underlying;
	uint public span;
	uint public end;
	uint public totalStaking;
	mapping(address => uint) public stakingOf;
	mapping(address => uint) public lasttimeOf;
	
	constructor(address _farm, address _underlying) public {
		initialize(msg.sender, _farm, _underlying);
	}
	
	function initialize(address governor, address _farm, address _underlying) public initializer {
	    super.initialize(governor);
	    
	    farm     = _farm;
	    underlying  = _underlying;
	    
	    IFarm(farm).crop();                         // just check
	    IERC20(underlying).totalSupply();           // just check
	}
    
    function setHarvestSpan(uint _span, bool isLinear) virtual override external governance {
        span = _span;
        if(isLinear)
            end = now + _span;
        else
            end = 0;
    }
    
    function farming(uint amount) virtual override external {
        farming(msg.sender, amount);
    }
    function farming(address from, uint amount) virtual override public {
        harvest();
        
        _farming(from, amount);
        
        stakingOf[msg.sender] = stakingOf[msg.sender].add(amount);
        totalStaking = totalStaking.add(amount);
        
        emit Farming(msg.sender, from, amount);
    }
    function _farming(address from, uint amount) virtual internal {
        underlying.safeTransferFrom(from, address(this), amount);
    }
    
    function unfarming() virtual override external returns (uint amount){
        return unfarming(msg.sender, stakingOf[msg.sender]);
    }
    function unfarming(uint amount) virtual override external returns (uint){
        return unfarming(msg.sender, amount);
    }
    function unfarming(address to, uint amount) virtual override public returns (uint){
        harvest();
        
        totalStaking = totalStaking.sub(amount);
        stakingOf[msg.sender] = stakingOf[msg.sender].sub(amount);
        
        _unfarming(to, amount);
        
        emit Unfarming(msg.sender, to, amount);
        return amount;
    }
    function _unfarming(address to, uint amount) virtual internal returns (uint){
        underlying.safeTransfer(to, amount);
        return amount;
    }
    
    function harvest() virtual override public returns (uint[] memory amounts) {
        return harvest(msg.sender);
    }
    function harvest(address to) virtual override public returns (uint[] memory amounts) {
        amounts = harvestCapacity(msg.sender);
        amounts = _harvest(to, amounts);
    
        lasttimeOf[msg.sender] = now;

        emit Harvest(msg.sender, to, amounts);
    }
    function _harvest(address to, uint[] memory amounts) virtual internal returns (uint[] memory) {
        if(amounts.length > 0 && amounts[0] > 0)
            IFarm(farm).crop().safeTransferFrom(farm, to, amounts[0]);
        return amounts;
    }
    
    function harvestCapacity(address farmer) virtual override public view returns (uint[] memory amounts) {
        if(span == 0 || totalStaking == 0)
            return amounts;
        
        uint amount = IERC20(IFarm(farm).crop()).allowance(farm, address(this));
        amount = amount.mul(stakingOf[farmer]).div(totalStaking);
        
        uint lasttime = lasttimeOf[farmer];
        if(end == 0) {                                                         // isNonLinear, endless
            if(now.sub(lasttime) < span)
                amount = amount.mul(now.sub(lasttime)).div(span);
        }else if(now < end)
            amount = amount.mul(now.sub(lasttime)).div(end.sub(lasttime));
        else if(lasttime >= end)
            amount = 0;
            
        amounts = new uint[](1);
        amounts[0] = amount;
    }
} 

contract SFarm is IFarm, Governable {
    using TransferHelper for address;

    address override public crop;

	constructor(address governor, address crop_) public {
		initialize(governor, crop_);
	}
	
    function initialize(address governor, address crop_) public initializer {
        super.initialize(governor);
        crop = crop_;
    }
    
    function approvePool(address pool, uint amount) public governance {
        crop.safeApprove(pool, amount);
    }
    
}


// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

