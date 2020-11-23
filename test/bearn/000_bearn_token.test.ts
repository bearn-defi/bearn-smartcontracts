import {ethers} from 'hardhat';
import {expect} from '../chai-setup';

import {
    fromWei,
    toWei,
    getBalance,
    maxUint256,
    ADDRESS_ZERO
} from '../shared/utilities';

import {
    Bfi, BfiFactory,
} from '../../typechain';

import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

const verbose = process.env.VERBOSE;

describe('000_bearn_token.test', function () {
    let signers: SignerWithAddress[];
    let deployer: SignerWithAddress;
    let bob: SignerWithAddress;
    let minter: SignerWithAddress;

    let bfiToken: Bfi;

    before(async function () {
        signers = await ethers.getSigners();
        deployer = signers[0];
        bob = signers[1];
        minter = signers[2];

        bfiToken = await new BfiFactory(deployer).deploy();
    })

    describe('BearnToken should work', () => {
        it('constructor parameters should be correct', async () => {
            expect(await bfiToken.governance()).is.eq(deployer.address);
            expect(await bfiToken.cap()).is.eq(toWei(210000));
        });

        it('parameters should be correct', async () => {
            expect(await bfiToken.publicFundPercent()).is.eq(5750);
            expect(await bfiToken.communityFundPercent()).is.eq(2000);
            expect(await bfiToken.teamFundPercent()).is.eq(1750);
            expect(await bfiToken.gameFundAmount()).is.eq(toWei(10500));
        });

        it('mint by governance', async () => {
            await expect(async () => {
                await bfiToken.connect(deployer).mint(bob.address, toWei('10'));
            }).to.changeTokenBalances(bfiToken, [bob], [toWei('10')]);
        });

        it('mint by minter', async () => {
            expect(await bfiToken.minters(minter.address)).is.false;
            await expect(bfiToken.connect(minter).mint(bob.address, toWei('10')))
                .to.revertedWith('!governance && !minter');
            await bfiToken.addMinter(minter.address);
            expect(await bfiToken.minters(minter.address)).is.true;
            await expect(async () => {
                await bfiToken.connect(minter).mint(bob.address, toWei('10'));
            }).to.changeTokenBalances(bfiToken, [bob], [toWei('10')]);
        });

        it('bob burn BFI', async () => {
            await expect(bfiToken.connect(bob).burn(toWei('100')))
                .to.revertedWith('burn amount exceeds balance');
            await expect(async () => {
                await bfiToken.connect(bob).burn(toWei('10'));
            }).to.changeTokenBalances(bfiToken, [bob], [toWei('-10')]);
        });

        it('cant mintFunds again (less than 72h)', async () => {
            await bfiToken.mintFunds(toWei('10'));
            await expect(bfiToken.mintFunds(toWei('10'))).to.revertedWith('less than 72h');
        });
    });
});
