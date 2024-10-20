// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PredictionToken {
    string public name = "Prediction Token";
    string public symbol = "PRED";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply) {
        totalSupply = initialSupply * 10**uint256(decimals);
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 value) public returns (bool success) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool success) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool success) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }
}

contract PredictionMarketWithPools {
    struct Pool {
        uint256 totalTokens;
        mapping(address => uint256) userTokens;
    }

    struct Market {
        string question;
        uint256 endTime;
        bool resolved;
        bool outcome;
        Pool yesPool;
        Pool noPool;

    }

    PredictionToken public token;
    address public owner;
    uint256 public marketIndex;
    
    mapping(uint256 => Market) private markets;

    
    
    event MarketCreated(uint256 indexed marketId, string question, uint256 endTime);
    event TokensAddedToPool(uint256 indexed marketId, address indexed user, bool isYesPool, uint256 amount);
    event MarketResolved(uint256 indexed marketId, bool outcome);
    event RewardsClaimed(uint256 indexed marketId, address indexed user, uint256 amount);

    constructor(address _tokenAddress) {
        token = PredictionToken(_tokenAddress);
        owner = msg.sender;
        marketIndex = 0;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    function createMarket(string memory _question, uint256 _duration) external onlyOwner {
        require(_duration > 0, "Duration must be positive");
        
        Market storage newMarket = markets[marketIndex];
        newMarket.question = _question;
        newMarket.endTime = block.timestamp + _duration;
        newMarket.resolved = false;
        
        emit MarketCreated(marketIndex, _question, newMarket.endTime);
        marketIndex++;
    }

    function addToPool(uint256 _marketId, bool _isYesPool, uint256 _amount) external {
        require(_amount > 0, "Amount must be greater than 0");
        Market storage market = markets[_marketId];
        require(!market.resolved, "Market already resolved");
        require(block.timestamp < market.endTime, "Market has ended");

        // Transfer tokens from user to contract
        require(token.transferFrom(msg.sender, address(this), _amount), "Token transfer failed");

        // Add tokens to the appropriate pool
        Pool storage pool = _isYesPool ? market.yesPool : market.noPool;
        pool.totalTokens += _amount;
        pool.userTokens[msg.sender] += _amount;

        emit TokensAddedToPool(_marketId, msg.sender, _isYesPool, _amount);
    }

    function resolveMarket(uint256 _marketId, bool _outcome) external onlyOwner {
        Market storage market = markets[_marketId];
        require(!market.resolved, "Market already resolved");
        require(block.timestamp >= market.endTime, "Market not ended yet");

        market.resolved = true;
        market.outcome = _outcome;

        emit MarketResolved(_marketId, _outcome);
    }

    function claimRewards(uint256 _marketId) external {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved yet");

        Pool storage winningPool = market.outcome ? market.yesPool : market.noPool;
        Pool storage losingPool = market.outcome ? market.noPool : market.yesPool;

        uint256 userTokens = winningPool.userTokens[msg.sender];
        require(userTokens > 0, "No tokens to claim");

        // Calculate rewards: original tokens + share of losing pool
        uint256 shareOfLosingPool = (userTokens * losingPool.totalTokens) / winningPool.totalTokens;
        uint256 totalReward = userTokens + shareOfLosingPool;

        // Reset user's tokens in the pool
        winningPool.userTokens[msg.sender] = 0;

        // Transfer rewards
        require(token.transfer(msg.sender, totalReward), "Reward transfer failed");

        emit RewardsClaimed(_marketId, msg.sender, totalReward);
    }

    function getPoolInfo(uint256 _marketId) external view returns (
        uint256 yesPoolTotal,
        uint256 noPoolTotal,
        uint256 userYesTokens,
        uint256 userNoTokens
    ) {
        Market storage market = markets[_marketId];
        return (
            market.yesPool.totalTokens,
            market.noPool.totalTokens,
            market.yesPool.userTokens[msg.sender],
            market.noPool.userTokens[msg.sender]
        );
    }

    function getMarketInfo(uint256 _marketId) external view returns (
        string memory question,
        uint256 endTime,
        bool resolved,
        bool outcome
    ) {
        Market storage market = markets[_marketId];
        return (
            market.question,
            market.endTime,
            market.resolved,
            market.outcome
        );
    }

    function calculatePotentialReward(uint256 _marketId, bool _isYesPool, uint256 _amount) external view returns (uint256) {
        Market storage market = markets[_marketId];
        Pool storage pool = _isYesPool ? market.yesPool : market.noPool;
        Pool storage oppositePool = _isYesPool ? market.noPool : market.yesPool;
        
        uint256 newPoolTotal = pool.totalTokens + _amount;
        return _amount + (_amount * oppositePool.totalTokens) / newPoolTotal;
    }
}