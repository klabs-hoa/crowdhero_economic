//SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.4-solc-0.7/contracts/token/ERC20/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.4-solc-0.7/contracts/math/SafeMath.sol";

contract TimelockDepartment {
    using SafeERC20 for IERC20;
    using SafeMath  for uint256;

    // ERC20 basic token contract being held
    IERC20  private _token;
    address private _owner;
    uint256 private _minDate;
    uint256 private _totalBudget;

    struct Member {
        uint256     budget;
        uint256     bonus;
        address     wallet;
        uint256     startDate;
        uint        maxTimes;
        string      department;
    }

    struct Department {
        uint256     budget;
        uint        lockDuration;  
        uint        bonusDuration;
    }

    mapping(string  => Department)  private _departments;
    mapping(address => Member)      private _members;
    mapping(address => uint256)     private _lastday;
    mapping(address => uint256)     private _receipts;
    mapping(address => bool)        private _operators;

    constructor(address[] memory operators_,uint256 minDate_, uint256 totalBudget_) {
        _owner = msg.sender;
        for(uint i=0; i < operators_.length; i++){
            address opr = operators_[i];
            require( opr != address(0), "invalid operator");
            _operators[opr] = true;
        }
        _minDate        = minDate_;
        _totalBudget    = totalBudget_;
    }

    /**
     * add department
     */
    function addDepartment(string memory name_, uint256 budget_, uint lockDuration_, uint bonusDuration_ ) public {
        require( _owner == msg.sender, "only for owner");
        require(_departments[name_].bonusDuration < 1, "exist department");
        require(_totalBudget    >= budget_, "invalid budget");
        _totalBudget            = _totalBudget - budget_;
        
        Department storage dept = _departments[name_];
        dept.budget             = budget_;
        dept.lockDuration       = lockDuration_;
        dept.bonusDuration      = bonusDuration_;
        
        emit DepartmentEvent(name_, budget_, lockDuration_, bonusDuration_, "add");
    }

    /**
     * add member
     */
    function addMember(string memory department_, address wallet_, uint256 bonus_ , uint maxTimes_, uint256 startDate_) public {
        require(_operators[msg.sender], "only for operator");
        require(_departments[department_].bonusDuration > 1, "invalid department");
        require(bonus_              > 0, "invalid bonus");
        require(maxTimes_           > 0, "invalid maxTime");
        require(_members[wallet_].bonus    < 1, "exist memberber");
        require(startDate_          >= _minDate, "invalid start date");
        require(bonus_*maxTimes_    <= _departments[department_].budget, "invalid total budget");
        
        Department storage dept =  _departments[department_];
        uint256 memBudget       = bonus_*maxTimes_;
        dept.budget             = dept.budget - memBudget;
        _lastday[wallet_]       = startDate_ + dept.lockDuration;
        _receipts[wallet_]      = 0;
        
        Member storage mem      = _members[wallet_];
        mem.budget              = memBudget;
        mem.bonus               = bonus_;
        mem.wallet              = wallet_;
        mem.startDate           = startDate_;
        mem.maxTimes            = maxTimes_;
        mem.department          = department_;

        emit MemberEvent(department_, wallet_, bonus_, maxTimes_, block.timestamp, _lastday[wallet_], "add");
    }

    function removeMember(string memory department_, address wallet_) public {
        require( _owner == msg.sender, "only for owner");
        require(_departments[department_].bonusDuration > 1, "invalid department");
        require(_members[wallet_].budget    > 1, "invalid memberber");
        
        Member storage mem      = _members[wallet_];
        uint256 memBudget       = mem.budget;
        mem.budget              = 0;
        
        Department storage dept =  _departments[department_];
        dept.budget             = dept.budget + memBudget;
        
        emit MemberEvent(department_, wallet_, _receipts[wallet_], _receipts[wallet_]/mem.bonus, block.timestamp, _lastday[wallet_], "remove");
        
    }
    /**
     * get total budget
     */
    function getBudget() public view returns (uint256) {
        return _totalBudget;
    }

    /**
     * get value of department
     */
    function getDepartmentBudget(string memory name_) public view  returns (uint256) {
        require(_departments[name_].bonusDuration > 0,"not exists");
        return _departments[name_].budget;
    }

    /**
     * get value of budget member
     */
    function getMemberBudget(address wallet_) public view  returns (uint256) {
        require(_members[wallet_].bonus > 0,"not exists");
        return _members[wallet_].budget;
    }
    
    /**
     * get total value of member
     */
    function getMemberReceipt(address wallet_) public view returns (uint256) {
        require(_receipts[wallet_] > 0, "not exists");
        return _receipts[wallet_];
    }

    /**
     * get total value of member
     */
    function getMemberNextDate(address wallet_) public view returns (uint256) {
        require(_lastday[wallet_] > 0, "not exists");
        return _lastday[wallet_];
    }
    
    /**
     * add token of contract
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
     * get total value of member
     */
    function checkCount(address receiver_) public view returns (uint256) {
        uint256 lastDate        = _lastday[receiver_];
        Member memory mem       = _members[receiver_];
        Department memory dep   = _departments[mem.department];
        require(lastDate + dep.bonusDuration <= block.timestamp, "wait for next time");
        uint countDuration      = (uint(block.timestamp - lastDate)/dep.bonusDuration);
        if(countDuration > mem.maxTimes )
            countDuration       = mem.maxTimes;
        return countDuration;
    }
    
    /**
     * get total value of member
     */
    function checkBonus(address receiver_) public view returns (uint256) {
        require( _members[receiver_].budget > 0 || _operators[msg.sender] || (_owner == msg.sender), "invalid permission");
        Member memory mem       = _members[receiver_];
        
        uint countDuration      = checkCount(receiver_);
        require(countDuration   > 0, "invalid count");
        uint256 bonus           = countDuration * mem.bonus;
        if(bonus > mem.budget )
            bonus               = mem.budget;
        require(bonus                           > 0, "empty bonus");    
        require(_receipts[receiver_] + bonus    <= mem.maxTimes * mem.bonus, "invalid bonus");
        return bonus;
    }
    
    /**
     * @notice Transfers tokens held by department to member.
     */
    function releaseFor(address receiver_) public {
        uint256 lastDate        = _lastday[receiver_];
        Member storage mem      = _members[receiver_];
        Department memory dep   = _departments[mem.department];
       
        uint256 countDuration   = checkCount(receiver_);
        uint256 bonus           = checkBonus(receiver_);
        

        uint256 amount = token().balanceOf(address(this));
        require(amount >= bonus, "not enough tokens");
        
        mem.budget              = mem.budget - bonus;
        _receipts[receiver_]    = _receipts[receiver_] + bonus;
        _lastday[receiver_]     = lastDate + (countDuration*dep.bonusDuration);
        token().safeTransfer(receiver_, bonus);

        emit ReleaseEvent(receiver_, bonus, _receipts[receiver_], _lastday[receiver_]);
    }

    event ReleaseEvent(address indexed owner, uint256 indexed bonus, uint256 total, uint256 lastDate);
    event DepartmentEvent(string indexed name, uint256 indexed budget, uint lock, uint duration, string action);
    event MemberEvent(string indexed department, address indexed wallet, uint256 bonus, uint times, uint256 createDate, uint256 lastRelease, string action);
}