// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./SMinter.sol";
import "./Proxy.sol";

contract CurveGauge is SSimpleGauge {

	function initialize(address governor, address _minter, address _lp_token, address _rewarded_token) public initializer {
	    super.initialize(governor, _minter, _lp_token);
	    
	    rewarded_token = _rewarded_token;
	    IERC20(_rewarded_token).totalSupply();           // just check
	}
    
    function claim_rewards(address addr) override public {
        rewarded_token.safeTransfer(addr, 10);
    }
    function claimable_reward(address addr) override public view returns (uint) {
        addr;
        return 10;
    }
}


contract CurveToken is ERC20 {

	constructor(address recipient) ERC20("CRV Token for Test", "CRV") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


contract RewardToken is ERC20 {

	constructor(address recipient) ERC20("SNX Reward for Test", "SNX") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


contract LPToken is ERC20 {

	constructor(address recipient) ERC20("LPToken for Test", "LPT") public {
		uint8 decimals = 0;
		_setupDecimals(decimals);
		
		_mint(recipient,  1000000 * 10 ** uint256(decimals));
	}
}


struct S {
    address pcMinter;
    address pcsGauge;
    address psMinter;
    address pssGauge;
    
    address CRV;
    address SNX;
    address SFG;
    address LPT;
    
    address cMinter;
    address sMinter;
    address csGauge;
    address ssGauge;
}
    
contract DeployMinter {
    event Deploy(string name, address addr);
    
    //function deploy(address adminProxy, address admin) public {
    constructor(address adminProxy, address admin) public {
        S memory s;
        
        s.pcMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pcsGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        s.psMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pssGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        
        s.CRV       = address(new CurveToken(  s.pcMinter ));                           
        s.SNX       = address(new RewardToken( s.pcsGauge ));                           
        s.SFG       = address(new SfgToken(    s.psMinter ));                           
        s.LPT       = address(new LPToken(     admin      ));                           

        s.cMinter   = address(new SMinter());                                           
        s.sMinter   = address(new SMinter());                                           

        emit Deploy('pcMinter', s.pcMinter);
        emit Deploy('pcsGauge', s.pcsGauge);
        emit Deploy('psMinter', s.psMinter);
        emit Deploy('pssGauge', s.pssGauge);
        emit Deploy('CRV', s.CRV);
        emit Deploy('SNX', s.SNX);
        emit Deploy('SFG', s.SFG);
        emit Deploy('LPT', s.LPT);
        emit Deploy('cMinter', s.cMinter);
        emit Deploy('sMinter', s.sMinter);
        
        selfdestruct(msg.sender);
    }
}
    
contract DeployGauge {
    event Deploy(bytes32 name, address addr);
    
    //constructor(address adminProxy, address admin, S memory s) public {
    function deploy(address adminProxy, address admin, S memory s) public {
        s.csGauge   = address(new CurveGauge());                                        emit Deploy('csGauge', s.csGauge);
        s.ssGauge   = address(new SNestGauge());                                        emit Deploy('ssGauge', s.ssGauge);
        
        IProxy(s.pcMinter).initialize(adminProxy, s.cMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.CRV));
        IProxy(s.pcsGauge).initialize(adminProxy, s.csGauge, abi.encodeWithSignature('initialize(address,address,address,address)', address(this), s.pcMinter, s.LPT, s.SNX));
        IProxy(s.psMinter).initialize(adminProxy, s.sMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.SFG));
        IProxy(s.pssGauge).initialize(adminProxy, s.ssGauge, abi.encodeWithSignature('initialize(address,address,address,address,address[])', address(this), s.psMinter, s.LPT, s.pcsGauge, new address[](0)));
        
        SMinter(s.pcMinter).setGaugeQuota(s.pcsGauge, IERC20(s.CRV).totalSupply());
        CurveGauge(s.pcsGauge).setSpan(IERC20(s.CRV).totalSupply(), true);
        
        SMinter(s.psMinter).setGaugeQuota(s.pssGauge, IERC20(s.SFG).totalSupply());
        SNestGauge(s.pssGauge).setSpan(IERC20(s.SFG).totalSupply() / 1 ether, false);
        
        Governable(s.pcMinter).transferGovernorship(admin);
        Governable(s.pcsGauge).transferGovernorship(admin);
        Governable(s.psMinter).transferGovernorship(admin);
        Governable(s.pssGauge).transferGovernorship(admin);

        selfdestruct(msg.sender);
    }
}

interface IProxy {
    function initialize(address _admin, address _logic, bytes memory _data) external payable;
}
