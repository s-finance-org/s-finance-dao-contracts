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
        rewarded_token.safeTransfer(addr, 10000);
    }
    function claimable_reward(address addr) override public view returns (uint) {
        addr;
        return 10000;
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
    address pgMinter;
    address pgsGauge;
    //address pyMinter;
    
    address CRV;
    address SNX;
    address SFG;
    address LPT;
    
    address cMinter;
    address gMinter;
    address csGauge;
    address gsGauge;
}
    
contract DeployMinter {
    event Deploy(string name, address addr);
    
    //function deploy(address adminProxy, address admin) public {
    constructor(address adminProxy, address admin) public {
        S memory s;
        
        s.pcMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pcsGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pgMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        s.pgsGauge  = address(new InitializableAdminUpgradeabilityProxy());             
        //s.pyMinter  = address(new InitializableAdminUpgradeabilityProxy());             
        
        s.CRV       = address(new CurveToken(  s.pcMinter ));                           
        s.SNX       = address(new RewardToken( s.pcsGauge ));                           
        s.SFG       = address(new SfgToken(    s.pgMinter ));                           
        s.LPT       = address(new LPToken(     admin      ));                           

        s.cMinter   = address(new SMinter());                                           
        s.gMinter   = address(new SMinter());                                           

        emit Deploy('pcMinter', s.pcMinter);
        emit Deploy('pcsGauge', s.pcsGauge);
        emit Deploy('pgMinter', s.pgMinter);
        emit Deploy('pgsGauge', s.pgsGauge);
        //emit Deploy('pyMinter', s.pyMinter);
        emit Deploy('CRV', s.CRV);
        emit Deploy('SNX', s.SNX);
        emit Deploy('SFG', s.SFG);
        emit Deploy('LPT', s.LPT);
        emit Deploy('cMinter', s.cMinter);
        emit Deploy('gMinter', s.gMinter);
        
        selfdestruct(msg.sender);
    }
}
    
contract DeployGauge {
    event Deploy(bytes32 name, address addr);
    
    //constructor(address adminProxy, address admin, S memory s) public {
    function deploy(address adminProxy, address admin, S memory s) public {
        s.csGauge   = address(new CurveGauge());                                        emit Deploy('csGauge', s.csGauge);
        s.gsGauge   = address(new SNestGauge());                                        emit Deploy('gsGauge', s.gsGauge);
        
        IProxy(s.pcMinter).initialize(adminProxy, s.cMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.CRV));
        IProxy(s.pcsGauge).initialize(adminProxy, s.csGauge, abi.encodeWithSignature('initialize(address,address,address,address)', address(this), s.pcMinter, s.LPT, s.SNX));
        IProxy(s.pgMinter).initialize(adminProxy, s.gMinter, abi.encodeWithSignature('initialize(address,address)', address(this), s.SFG));
        IProxy(s.pgsGauge).initialize(adminProxy, s.gsGauge, abi.encodeWithSignature('initialize(address,address,address,address,address[])', address(this), s.pgMinter, s.LPT, s.pcsGauge, new address[](0)));
        
        SMinter(s.pcMinter).setGaugeQuota(s.pcsGauge, IERC20(s.CRV).totalSupply());
        CurveGauge(s.pcsGauge).setSpan(IERC20(s.CRV).totalSupply(), true);
        
        SMinter(s.pgMinter).setGaugeQuota(s.pgsGauge, IERC20(s.SFG).totalSupply());
        SNestGauge(s.pgsGauge).setSpan(IERC20(s.SFG).totalSupply() / 1 ether, false);
        
        SNestGauge(s.pgsGauge).setConfig('devAddr', uint(msg.sender));
        SNestGauge(s.pgsGauge).setConfig('devRatio', 0.05 ether);
        SNestGauge(s.pgsGauge).setConfig('ecoAddr', uint(0x445DfB4d52b7BCA4557Dd6df8ca8D2D2a7a832d6));
        SNestGauge(s.pgsGauge).setConfig('ecoAddr', 0.05 ether);

        Governable(s.pcMinter).transferGovernorship(admin);
        Governable(s.pcsGauge).transferGovernorship(admin);
        Governable(s.pgMinter).transferGovernorship(admin);
        Governable(s.pgsGauge).transferGovernorship(admin);

        selfdestruct(msg.sender);
    }
}

interface IProxy {
    function initialize(address _admin, address _logic, bytes memory _data) external payable;
}
