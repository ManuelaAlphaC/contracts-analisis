// SPDX-License-Identifier: MIT
 
pragma solidity ^0.8.15;
 
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
 
// chiama la funzione OwnerOf del contratto ERC721 della collezione NFT background arancione
abstract contract ERC721 {
   function ownerOf(uint256 tokenId) public view virtual returns (address);
}
 
// chiama la funzione forgeToken del contratto ERC721 della collezione NFT background arancione
abstract contract ForgeTokenContract {
   function forgeToken(uint256 amount, uint256 tokenId, address owner) public virtual;
}
 
contract RedeemableToken is ERC1155, Ownable, ERC1155Burnable {   
   constructor() ERC1155("") {
       tokenURIs[1] = "https://rtfkt.mypinata.cloud/ipfs/QmRbUSDAFLf5iEuU9v49Vt7YppyCjGsJQMxqrt6PWF5RF6/1";
   }
 
   // address del contratto che permette il riscatto del NFT ERC721
   address redemptionMiddlewareContract = 0x8E5474cA17499626EE88E2A533bD369EBe72099A;
 
   mapping (uint256 => uint256) public currentSupply;
   mapping (uint256 => uint256) public supplyLimit;
   mapping (uint256 => mapping (address => mapping(uint256 => address))) redeemedToken;
   mapping (uint256 => address) public forgingContractAddresses;
   mapping (address => uint256) public authorizedCollections; // Imposta il tokenID di conio associato alla raccolta
   mapping (uint256 => string) public tokenURIs;
 
   // Mint function
   function redeem(address owner, address initialCollection, uint256 tokenId) public payable returns(uint256) {
       // questa funzione viene chiamata dal redeem contract ovvero gli utenti interagiscono
       // con la funzione del mint attraverso il contratto RTFKTRedemption (0x8E547)
       require(msg.sender == redemptionMiddlewareContract, "Not authorized");
      
       // se il contratto è autorizzato quindi è il contratto di Clon X o Dunks
       require(authorizedCollections[initialCollection] != 0, "Collection not authorized");
      
       // viene effettuato il controllo della supply, in modo che non venga superato il massimo di token disponibili
       require(currentSupply[authorizedCollections[initialCollection]] + 1 <= supplyLimit[authorizedCollections[initialCollection]], "Limit reached");
      
       // initialCollection sta per Clon X o Dunks e l'address del contratto ERC721
       // il suo valore è attribuito alla variabile collectionRedeem
       ERC721 collectionRedeem = ERC721(initialCollection);
      
       // viene fatto il controllo per verificare la proprietà dei
       // token che fanno parte della collezione ClonX o Dunks
       require(collectionRedeem.ownerOf(tokenId) == owner, "Don't own that token");
 
       // viene fatto il controllo per verificare se il token è stato già riscatatto
       require(redeemedToken[authorizedCollections[initialCollection]][initialCollection][tokenId] == 0x0000000000000000000000000000000000000000, "Token redeemd already");
      
       // la currentSupply aumenta di 1
       currentSupply[authorizedCollections[initialCollection]] = currentSupply[authorizedCollections[initialCollection]] + 1;
      
       // viene reggistratto il token appena riscatato dal mitente nella mapping dei token già riscatatti
       redeemedToken[authorizedCollections[initialCollection]][initialCollection][tokenId] = owner;
 
       // viene mintato un NFT ERC1155 con il background blu
       _mint(owner, authorizedCollections[initialCollection], 1, "");
 
       return 1;
   }
 
   // puoi riscattare più token contemporaneamente soltanto se fanno parte della stessa collezione
   // vengono fatti i stessi controlli della funzione commentata sopra
   function redeemBatch(address owner, address initialCollection, uint256[] calldata tokenIds) public payable {
       require(msg.sender == redemptionMiddlewareContract, "Not authorized");
       require(tokenIds.length > 0, "Mismatch of length");
       require(authorizedCollections[initialCollection] != 0, "Collection not authorized");
       require(currentSupply[authorizedCollections[initialCollection]] + tokenIds.length <= supplyLimit[authorizedCollections[initialCollection]], "Limit reached");
       ERC721 collectionRedeem = ERC721(initialCollection);
 
       for(uint256 i = 0; i < tokenIds.length; ++i) {
           require(redeemedToken[authorizedCollections[initialCollection]][initialCollection][tokenIds[i]] == 0x0000000000000000000000000000000000000000, "Token redeemd already");
           require(collectionRedeem.ownerOf(tokenIds[i]) == owner, "Don't own that token");
           redeemedToken[authorizedCollections[initialCollection]][initialCollection][tokenIds[i]] = owner;
       }
 
       currentSupply[authorizedCollections[initialCollection]] = currentSupply[authorizedCollections[initialCollection]] + tokenIds.length;
 
       _mint(owner, authorizedCollections[initialCollection], tokenIds.length, "");
   }
 
   /* Funzione di forgiatura
      arrivato il momento in cui gli NFT ERC1155 possono essere forgiati
      per una felpa con cappuccio e un NFT ERC721 che ne rappresenta il possesso fisico della felpa
      l'utente dovrà inserire nell'input l'id del NFT ERC1155 che intende forgiare e la quantità
   */
   function forgeToken(uint256 tokenId, uint256 amount) public {
       // verifica se il tokenId dato in input fa parte dei token che possono essere forgiati
       require(forgingContractAddresses[tokenId] != 0x0000000000000000000000000000000000000000, "No forging address set for this token");
      
       // verifica la proprietà della quantità di token data in input
       require(balanceOf(msg.sender, tokenId) >= amount, "Doesn't own the token"); // Check if the user own one of the ERC-1155
      
       // il token ERC1155 viene bruciato
       burn(msg.sender, tokenId, amount);
      
       ForgeTokenContract forgingContract = ForgeTokenContract(forgingContractAddresses[tokenId]);
      
       // viene coniato il token NFT ERC-721 (background arancione)
       forgingContract.forgeToken(amount, tokenId, msg.sender);
   }
 
   // funzione Airdrop di NFT ERC1155
   function airdropTokens(uint256[] calldata tokenIds, uint256[] calldata amount, address[] calldata owners) public onlyOwner {
       for(uint256 i = 0; i < tokenIds.length; ++i) {
           _mint(owners[i], tokenIds[i], amount[i], "");
       }
   }
 
   // --------
   // Getter
   // --------
   // restituisce l'address dell'utente che ha riscatatto un determinato NFT ERC1155
   function hasBeenRedeem(address initialCollection, uint256 tokenId) public view returns(address) {
       return redeemedToken[authorizedCollections[initialCollection]][initialCollection][tokenId];
   }
 
   // restituisce l'uri dei metadata del NFT
   function uri(uint256 tokenId) public view virtual override returns (string memory) {
       return tokenURIs[tokenId];
   }
 
   // --------
   // Setter
   // --------
 
   function setTokenURIs(uint256 tokenId, string calldata newUri) public onlyOwner {
       tokenURIs[tokenId] = newUri;
   }
 
   function setSupply(uint256 tokenId, uint256 newSupply) public onlyOwner {
       supplyLimit[tokenId] = newSupply;
   }
 
   function setForgingAddress(uint256 tokenId, address forgingAddress) public onlyOwner {
       forgingContractAddresses[tokenId] = forgingAddress;
   }
 
   function setAuthorizedCollection(address authorizedCollection, uint256 tokenId) public onlyOwner {
       // se il tokenId è 0 allora l'autorizzazione alla raccolta verrà annullata
       authorizedCollections[authorizedCollection] = tokenId;
   }
 
   function setMiddleware(address newContractAddress) public onlyOwner {
       redemptionMiddlewareContract = newContractAddress;
   }
 
   // Nel caso qualcuno invii denaro al contratto per errore
   function withdrawFunds() public onlyOwner {
       payable(msg.sender).transfer(address(this).balance);
   }
}
