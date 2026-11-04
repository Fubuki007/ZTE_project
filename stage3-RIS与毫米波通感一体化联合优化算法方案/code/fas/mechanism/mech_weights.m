function weights=mech_weights(dd_loss_db)
% A reciprocal BS-target obstruction attenuates DD twice and RD/DR once.
assert(isscalar(dd_loss_db) && isfinite(dd_loss_db) && dd_loss_db>=0);
hop=10^(-dd_loss_db/40); weights=[hop^2 hop hop 1];
end
