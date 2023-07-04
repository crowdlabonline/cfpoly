// SPDX-License-Identifier: MIT

/// @custom:security-contact security@cfpoly.io

pragma solidity ^0.8.18;


import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./CFPS.sol";

abstract contract Support
{
    function balanceOf(address account, uint256 id) public view virtual returns (uint256);
}

contract CFPoly is
ERC1155,
Ownable,
Pausable,
ERC1155Supply,
ERC2981,
ReentrancyGuard
{
    constructor() ERC1155("")
    {
        _manager = msg.sender;
    }

    mapping(address => uint256) publisher2Campaign;
    mapping(uint256 => address) campaignId2Publisher;
    mapping(uint256 => uint256) campaignDonationCount;
    mapping(uint256 => uint256) campaignDissolved;

    mapping(uint256 => uint256) campaign2Balance;
    mapping(uint256 => uint256) campaign2Target;
    mapping(uint256 => uint) campaign2Start;
    mapping(uint256 => uint) campaign2End;

    mapping(uint256 => uint256) donation2Campaign;
    mapping(uint256 => address) donation2Donor;
    mapping(uint256 => uint256) donationAmount;

    uint256[] discountTokens;

    mapping(address => uint256) lostFunds;

    uint256 openCampaigns = 0;


    uint256 private campaignId = 1;
    uint256 private donationId = 1;
    uint256 private serviceFee = 100;
    uint256 private serviceFeeMultiplier = 1;
    uint256 private serviceFeeBalance = 0;
    uint256 private tokenUriMethod = 0;


    address _manager;
    string public constant name = "Crowdfunding Platform on Polygon";
    string public constant symbol = "CFPT";

    address supportContract;


    function setSupportContract(address sc) public onlyOwner
    {
        require(sc != address(0), "0 is not a valid address");
        supportContract = sc;
    }

    function setDiscountTokens(uint256[] memory ids) public onlyOwner
    {
        delete discountTokens;
        discountTokens = ids;
    }

    event UserSupporterTokenBalanceResult(uint256 indexed balance);

    function checkUserSupporterTokenBalance(address tokenOwner, uint256 tid) public returns (uint256)
    {
        Support sc = Support(supportContract);
        uint256 b = sc.balanceOf(tokenOwner, tid);
        emit UserSupporterTokenBalanceResult(b);
        return b;
    }

    function getCampaignInfo(uint256 cid) public view returns (address cPublisher, uint256 cDonationCount, uint256 cBalance, uint256 cTarget, uint256 cDissolved, uint cStart, uint cEnd)
    {
        return (campaignId2Publisher[cid], campaignDonationCount[cid], campaign2Balance[cid] - (campaign2Balance[cid] / serviceFee) * serviceFeeMultiplier, campaign2Target[cid], campaignDissolved[cid], campaign2Start[cid], campaign2End[cid]);
    }

    event EmergencyRefund(uint256 indexed donationId, address indexed recipient, uint256 indexed amount, uint256 linkedCampaign, uint timestamp);

    function emergencyRefund(uint256 targetDonationId) public onlyOwner nonReentrant
    {
        _emergencyRefund(targetDonationId);
    }

    function _emergencyRefund(uint256 targetDonationId) private onlyOwner
    {
        require(donation2Donor[targetDonationId] != address(0), CFPS.STR_INVALID_ADDRESS);
        require(donationAmount[targetDonationId] > 0, CFPS.STR_NO_FUNDS);

        address payable recipient = payable(donation2Donor[targetDonationId]);
        uint256 amount = donationAmount[targetDonationId];
        uint256 linkedCampaignId = donation2Campaign[targetDonationId];

        if (0 != linkedCampaignId)
        {
            campaignDonationCount[linkedCampaignId]--;

            /*
                If the linked campaign has been previously dissolved, then we need to remove it once the
                donations count reaches 0.
            */
            if ((0 != campaignDissolved[linkedCampaignId]) && (campaignDonationCount[linkedCampaignId] == 0))
            {
                _clearCampaignMappings(linkedCampaignId);
            }
        }
        recipient.transfer(amount);
        emit EmergencyRefund(targetDonationId, recipient, amount, linkedCampaignId, block.timestamp);
    }

    /*
        Backers should have the ability to revoke their donations.
        In such case, the backer should invoke the revokeDonation() function
        and specify the ID of the donation they want to revoke.
        The revokeDonation() function transfers back the donated funds to
        the backer, unless the campaign has been closed by the creator.

        It is possible to revoke donations from dissolved campaigns.
    */
    event DonationRevocation(address indexed donor, uint256 indexed cid, uint256 indexed did, uint256 amount);

    function revokeDonation(uint256 targetDonationId)  public nonReentrant
    {
        _revokeDonation(targetDonationId);
    }

    function _revokeDonation(uint256 targetDonationId)  private
    {
        require(balanceOf(msg.sender, targetDonationId) == 1, CFPS.STR_NOT_AUTHORIZED);
        require(donationAmount[targetDonationId] > 0, CFPS.STR_NO_FUNDS);
        if (campaign2End[donation2Campaign[targetDonationId]] > 0)
        {
            require((campaign2End[donation2Campaign[targetDonationId]] > block.timestamp), CFPS.STR_CLOSED_NOOP);
        }
        else
        {
            require(campaignDissolved[donation2Campaign[targetDonationId]] != 0, CFPS.STR_CAMPAIGN_CLOSED);
        }
        uint256 payment = donationAmount[targetDonationId];
        uint256 cid = donation2Campaign[targetDonationId];
        campaign2Balance[cid] -= donationAmount[targetDonationId];
        campaignDonationCount[donation2Campaign[targetDonationId]]--;
        delete donationAmount[targetDonationId];
        delete donation2Donor[targetDonationId];
        delete donationAmount[targetDonationId];
        delete donation2Campaign[targetDonationId];
        _burn(msg.sender, targetDonationId, 1);

        payable(msg.sender).transfer(payment);
        emit DonationRevocation(msg.sender, cid, targetDonationId, payment);

        if ((campaignDonationCount[cid] == 0) &&
            (campaignDissolved[cid] == 1))
        {
            _clearCampaignMappings(cid);
        }
    }

    event DonationReceived(address indexed donor, uint256 indexed campaignId, uint256 indexed donationId, uint256 amount);

    /*
        In order to make a donation to a specific campaign,
        the backer needs to send funds using the donate() function,
        where:

        targetCampaignId    - the ID of the receiving campaign.
        existingDonationId  - this parameter should be 0 unless the backer has
                              already donated to this specific campaign, in which
                              case it is suggested to specify the ID of the
                              already made donation and the funds would be
                              added to the existing one, rather than creating
                              a new donation.
    */
    function donate(uint256 targetCampaignId, uint256 existingDonationId) payable public nonReentrant
    {
        require(msg.value >= 100000, CFPS.STR_MINIMUM_DONATION);
        require(campaign2Start[targetCampaignId] < block.timestamp, CFPS.STR_NOT_STARTED);
        require(campaign2End[targetCampaignId] > block.timestamp, CFPS.STR_ENDED);

        uint256 did = targetCampaignId + donationId++;

        if (0 != existingDonationId)
        {
            require(balanceOf(msg.sender, existingDonationId) > 0, CFPS.STR_INVALID_DATA);
            did = existingDonationId;
            donationId--;
        }
        else
        {
            donation2Donor[did] = msg.sender;
            donation2Campaign[did] = targetCampaignId;
            campaignDonationCount[targetCampaignId]++;
            _mint(msg.sender, did, 1, "");
        }
        donationAmount[did] += msg.value;
        campaign2Balance[targetCampaignId] += msg.value;
        emit DonationReceived(msg.sender, targetCampaignId, did, msg.value);
    }

    /*
        Fundraiser campaigns created with malicious or harmful intent
        would be dissolved and the backers would be able to withdraw
        their donations.
    */
    function dissolveCampaign(uint256 cid) public onlyOwner
    {
        require(campaign2End[cid] != 0, CFPS.STR_CAMPAIGN_CLOSED);
        campaignDissolved[cid] = 1;
        campaign2End[cid] = 0;
        openCampaigns--;
        _clearCampaignMappings(cid);
    }


    /*
        Once the campaign is over, the creator may call the closeCampaign() function,
        where :

        cid             - the ID of the campaign (same as the id of the token which
                          was minted with the creation of the campaign).
        supporterToken  - if the creator owns a CFPoly.io Supporter Badge, they may
                          specify the ID of the badge here and receive a discount
                          on service fee.

        Once the campaign is closed, the campaign token remains with the creator.
    */
    event CampaignClosed(uint256 indexed campaignId, address indexed campaignPublisher, uint256 amount);

    function closeCampaign(uint256 cid, uint256 supporterTokenId) external
    {
        _closeCampaign(cid, supporterTokenId);
    }

    function _closeCampaign(uint256 cid, uint256 supporterTokenId) private nonReentrant
    {
        require(campaign2End[cid] != 0, CFPS.STR_CAMPAIGN_CLOSED);
        require(campaign2End[cid] < block.timestamp, CFPS.STR_STILL_RUNNING);
        require(msg.sender == campaignId2Publisher[cid], CFPS.STR_NOT_AUTHORIZED);

        uint256 supporterTokenBalance = (supporterTokenId != 0)? checkUserSupporterTokenBalance(msg.sender, supporterTokenId) : 0;

        uint256 campaignServiceFee = (campaign2Balance[cid] / serviceFee) * serviceFeeMultiplier;
        if (supporterTokenBalance != 0)
        {
            if (uint128(supporterTokenId) == 0)
            {
                campaignServiceFee /= 2;
            }
            else
            {
                for (uint256 i = 0; i < discountTokens.length; i++)
                {
                    if (discountTokens[i] == supporterTokenId)
                    {
                        campaignServiceFee /= 4;
                        campaignServiceFee *= 3;
                        break;
                    }
                }
            }
        }
        uint256 dueBalance = campaign2Balance[cid] - campaignServiceFee;
        _clearCampaignMappings(cid);
        openCampaigns--;

        if (dueBalance > 0)
        {
            address payable recipient = payable(campaignId2Publisher[cid]);
            serviceFeeBalance += campaignServiceFee;
            recipient.transfer(dueBalance);
        }

        emit CampaignClosed(cid, msg.sender, dueBalance);
    }

    function _clearCampaignMappings(uint256 cid) private
    {
        delete publisher2Campaign[campaignId2Publisher[cid]];
        delete campaign2Start[cid];
        delete campaign2End[cid];
    }

    /*
        It is possible to create campaigns by directly interfacing the contract.
        In this case one should invoke the createCampaign() function, where

        startDate - timestamp of the date and time when the campaign should begin
                    The startDate should, obviously, be in the future.
        endDate   - timestamp of the date and time when the campaign should end.
                    It is, again - obvious, that this should be in the more distant
                    future than the startDate.
        target    - The value, the creator expects to collect when the campaign
                    is over.

        Once a campaign is successfully created, the creator receives an ERC1155
        token with the ID of the campaign (it is, in fact, an ERC721 token, as
        each token has a unique ID.
    */
    event CampaignCreated(uint256 indexed campaignId, uint256 indexed targetValue, uint startDate, uint endDate);

    function createCampaign(uint startDate, uint endDate, uint256 target) public whenNotPaused nonReentrant
    {
        uint256 cid = _createCampaign(startDate, endDate, target);
        emit CampaignCreated(cid, target, startDate, endDate);
    }

    function _createCampaign(uint startDate, uint endDate, uint256 target) private returns (uint256)
    {
        require(publisher2Campaign[msg.sender] == 0, CFPS.STR_CAMPAIGN_LIMIT);
        require(startDate < endDate, CFPS.STR_INVALID_PERIOD);
        require(startDate > block.timestamp, CFPS.STR_INVALID_START);
        require(target > (serviceFee * 10), CFPS.STR_TARGET_TOO_LOW);

        uint256 cid = campaignId << 128;
        publisher2Campaign[msg.sender] = cid;
        campaignId2Publisher[cid] = msg.sender;
        campaign2Balance[cid] = 0;
        campaign2Target[cid] = target;
        campaign2Start[cid] = startDate;
        campaign2End[cid] = endDate;
        campaignId++;
        openCampaigns++;
        _mint(msg.sender, cid, 1, "");
        return cid;
    }

    function getDonationInfo(uint256 did) public view returns (uint256 dId, address donor, uint256 amount, uint256 cId)
    {
        return (did, donation2Donor[did], donationAmount[did], donation2Campaign[did]);
    }

    function getDonationAmount(uint256 did) public view returns (uint256)
    {
        return donationAmount[did];
    }

    function getDonationCampaign(uint256 did) public view returns (uint256)
    {
        return donation2Campaign[did];
    }

    function getDonor(uint256 did) public view returns (address)
    {
        return donation2Donor[did];
    }

    function getCampaignBalance(uint256 cid) public view returns (uint256)
    {
        return campaign2Balance[cid];
    }

    function publisherCampaign(address a) public view returns (uint256)
    {
        return publisher2Campaign[a];
    }

    /*
        The regular ERC1155 stuff
    */
    function setURI(string memory newUri) external onlyOwner
    {
        _setURI(newUri);
    }

    function contractURI() external view returns (string memory)
    {
        return string.concat(uri(0), "CFPT.json");
    }

    function tokenURI(uint256 tid) public view returns (string memory)
    {
        string memory _URI;
        if (tokenUriMethod == 0)
            _URI = (uint128(tid) == 0) ? string.concat(uri(0), "campaign.json") : string.concat(uri(0), "backer.json");
        else
            _URI = (uint128(tid) == 0) ? string.concat(uri(0), "campaign_", Strings.toString(tid), ".json") : string.concat(uri(0), "backer_", Strings.toString(tid), ".json");
        return _URI;
    }

    function uri(uint256 tid) public view virtual override returns (string memory)
    {
        if(0 == tid)
            return super.uri(0);
        return tokenURI(tid);
    }

    event TokenUriMethodSet(uint256 indexed newMethod);
    function setTokenUriMethod(uint256 newMethod) external onlyOwner
    {
        tokenUriMethod = newMethod;
        emit TokenUriMethodSet(tokenUriMethod);
    }

    function balance() public onlyOwner view returns (uint256)
    {
        return address(this).balance;
    }

    function getServiceFeeBalance() public onlyOwner view returns (uint256)
    {
        return serviceFeeBalance;
    }

    function withdrawServiceFee() public onlyOwner nonReentrant
    {
        _withdrawServiceFee();
    }
    function _withdrawServiceFee() private onlyOwner
    {
        require(serviceFeeBalance > 0, CFPS.STR_NO_FUNDS);
        payable(_manager).transfer(serviceFeeBalance);
        serviceFeeBalance = 0;
    }

    /*
        The initial service fee of this contract is 1%. It is,
        however, in our plans to gradually reduce it. The idea
        is to allow Creators to get as much as possible from
        their campaigns.
    */
    event ServiceFeeRateSet(uint256 indexed newRate);
    function setServiceFeeRate(uint256 newRate) public onlyOwner
    {
        /* It is not allowed to raise the service fee. The higher the value of this
           variable, the lower the resulting fee.
        */
        require(newRate > serviceFee, "Service fees may only go down");
        serviceFee = newRate;
        emit ServiceFeeRateSet(serviceFee);
    }

    event ServiceFeeMultiplierSet(uint256 newMultiplier);
    function setServiceFeeMultiplier(uint256 newMultiplier) public onlyOwner
    {
        /* Service fee cannot be higher than 1% */
        require(((serviceFee > 100) && (newMultiplier < 10)),"The resulting fee rate would be too high");
        serviceFeeMultiplier = newMultiplier;
        emit ServiceFeeMultiplierSet(serviceFeeMultiplier);
    }

    function getServiceFeeRate() public view onlyOwner returns (uint256)
    {
        return serviceFee;
    }

    function getServiceFeeMultiplier() public view onlyOwner returns (uint256)
    {
        return serviceFeeMultiplier;
    }

    /*
        Should someone send funds directly to the contract (in which case those
        would otherwise merely get lost), they will be able to withdraw them.
    */
    function getLost() public nonReentrant
    {
        _getLost();
    }

    function _getLost() private
    {
        require(lostFunds[msg.sender] != 0, "Nothing to withdraw");
        payable(msg.sender).transfer(lostFunds[msg.sender]);
        delete lostFunds[msg.sender];
    }

    /*
        New campaigns cannot be created when the contract is paused.
        However, existing campaigns need to operate as usual (receiving
        donations, that means; backers would still have the ability to
        make or withdraw donations).
        This comes handy if we ever decide to upgrade the contract -
        it would then be paused, and would allow a gradual switch to
        a newer contract.
    */
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
    internal
    whenNotPaused
    override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }


    /*
        People should not directly send funds to this contract.
        However, should this happen, they need to have a way to
        withdraw those funds back.

        The receive() and fallback() functions place those funds
        in a separate "box" called "lostFunds". Whoever sends
        funds directly, may withdraw them by calling the getLost()
        function.
    */
    event Received(address indexed, uint256 indexed);

    receive() external payable
    {
        lostFunds[msg.sender] += msg.value;
        emit Received(msg.sender, msg.value);
    }

    event FallBack(address indexed, uint256 indexed);

    fallback() external payable
    {
        lostFunds[msg.sender] += msg.value;
        emit FallBack(msg.sender, msg.value);
    }

    /*
        Creators and backers thereof may, should they wish,
        sell their Creator or Backer tokens.
    */
    function _setRoyaltiesRecipient(address newRecipient) private
    {
        require(newRecipient != address(0), CFPS.STR_INVALID_ADDRESS);
        _manager = newRecipient;
    }

    function setRoyaltiesRecipient(address newRecipient) external onlyOwner
    {
        _setRoyaltiesRecipient(newRecipient);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice) public view override returns (address recipient, uint256 amount)
    {
        uint256 percent = 600;
        if (_tokenId >= (1 << 128))
            percent = 1000;

        return (_manager, (_salePrice * percent) / 10000);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC2981) returns (bool)
    {
        return (interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId));
    }
}