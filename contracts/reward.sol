//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.4-solc-0.7/contracts/token/ERC20/SafeERC20.sol";

contract RevenueReward {
    using SafeERC20 for IERC20;
    using SafeMath  for uint256;
    mapping(address => bool)        private _operators;

    // ERC20 basic token contract being held
    IERC20  private _token;
    address private _owner;

    uint256 private _budget;  // 159 mils CRWD
    uint256 private _count;  // count release
    
    mapping(uint256 => uint256)                     private _releases;   // release -> date
    mapping(uint256 => uint256)                     private _crwds;      // count -> crwd amount
    mapping(uint256 => uint256)                     private _fiats;      // count -> fiat amount
    mapping(uint256 => uint256)                     private _spends;     // count -> crwd spend
    mapping(address => mapping(uint256 => uint256)) private _receipts;   // receiver -> count -> crwd amount 
    mapping(address => uint256)                     private _receivers;  // list receiver address -> start with count
    mapping(address => uint256)                     private _rewards;    // list receiver address -> total reward
    
    constructor( uint256 startdate_, address[] memory operators_)
    {
        _budget             = 159000000;
        _count              = 0;
        _releases[_count]   = startdate_;
        _crwds[_count]      = 0;
        _fiats[_count]      = 0;
        _owner              = msg.sender;
        
        for(uint i=0; i < operators_.length; i++){
            address opr = operators_[i];
            require( opr != address(0), "invalid operator");
            _operators[opr] = true;
        }
    }

  
    /**
     * @return the remain token 
     */
    function getBudget() public view returns (uint256) {
        return _budget;
    }
    
    /**
     * @return current count
     */
    function getCount() public view returns (uint256) {
        return _count;
    }
    
    /**
     * @return current count
     */
    function getCrwd(uint256 count_) public view returns (uint256) {
        require(_count >= count_, "invalid count");
        return _crwds[count_];
    }
    
    /**
     * @return current count
     */
    function getFiat(uint256 count_) public view returns (uint256) {
        require(_count >= count_, "invalid count");
        return _fiats[count_];
    }
    
    /**
     * @return current count
     */
    function getSpend(uint256 count_) public view returns (uint256) {
        require(_count >= count_, "invalid count");
        return _spends[count_];
    }
    
    /**
     * set token
     */
    function setToken(IERC20 token_) public {
        require( _owner == msg.sender, "only for owner");
        _token = token_;
    }

    /**
     * @return the token being held.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * get receiver start with count
     */
    function getReceiverStart(address beneficiary_) public view returns (uint256) {
        return _receivers[beneficiary_];
    }
    
    /**
     * get receive each time
     */
    function getReceipt(address beneficiary_, uint256 count_) public view returns (uint256) {
        require(_receivers[beneficiary_] > 0, "invalid receiver");
        require(_count >= count_, "invalid count");
        
        return _receipts[beneficiary_][count_];
    }
    
    /**
     * total receive
     */
    function getTotalReward(address beneficiary_) public view returns (uint256) {
        return _rewards[beneficiary_];
    }
    
    /**
     * contract will get reward from count
     */
    function addReceiver(address beneficiary_, uint256 count_ ) public  {
        require(_operators[msg.sender], "only for operator");
        require(_receivers[beneficiary_] < 1, "already receiver");
        require(_count <= count_, "invalid count");
        
        _receivers[beneficiary_]   = count_;
        _rewards[beneficiary_]     = 0;
        emit ReceiverEvent(beneficiary_, "add");
    }

    function stopReceiver(address beneficiary_ ) public {
        require(_operators[msg.sender], "only for operator");
        require(_receivers[beneficiary_] > 0, "already remove");
        
        _receivers[beneficiary_]   = 0;
        emit ReceiverEvent(beneficiary_, "stop");
    }

    /**
     * @notice release bonus at first day of month
     */
    function rewardAt(uint256 count_, uint256 fiat_, uint256 crwd_) public {
        require( _operators[msg.sender], "only for operator");
        require( _count + 1 == count_, "invalid count");
        require( _releases[_count] + 2505600 < block.timestamp, "invalid date"); // 29 days
        require( _budget >= crwd_, "invalid crwd");
        
        _releases[count_]   = block.timestamp;
        _crwds[count_]      = crwd_;
        _fiats[count_]      = fiat_;
        _spends[count_]     = crwd_;
        
        _budget             = _budget - crwd_;
        _count              = count_;
        
        emit RewardEvent(_count, fiat_, crwd_);
    }

    /**
     * @notice Transfers tokens to 
     */
    function sendReward(uint256 count_, uint256 crwd_, address receiver_) external {
        require( _operators[msg.sender], "only for operator");
        require( _count                       == count_, "invalid count");
        require( _spends[count_]              >= crwd_, "invalid amount");
        require( _receivers[receiver_]        > 0, "not receiver");
        require( _receivers[receiver_]        <= count_, "invalid count");
        require( _receipts[receiver_][count_] < 1, "already get this month");
        
        _spends[count_]                 = _spends[count_] - crwd_;
        _receipts[receiver_][count_]    = crwd_;
        _rewards[receiver_]             = _rewards[receiver_] + crwd_;
        token().safeTransfer(receiver_, crwd_);
        
        emit SendEvent(_count, _crwds[count_], crwd_);
    }

    event ReceiverEvent(address owner, string indexed action);
    event RewardEvent(uint256 count, uint256 fiat, uint256 crwd);
    event SendEvent(uint256 count, uint256 total, uint256 crwd);
}