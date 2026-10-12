function ris_sic_save_atomic(path_name, data)
% Explicit struct avoids save() looking for variables in a helper's scope.
folder = fileparts(path_name);
tmp_name = [tempname(folder) '.mat'];
cleanup = onCleanup(@() remove_temporary(tmp_name));
save(tmp_name, '-struct', 'data', '-v7');
[ok, msg] = movefile(tmp_name, path_name, 'f');
if ~ok, error('RIS:CheckpointCommit', 'Atomic checkpoint move failed: %s', msg); end
end

function remove_temporary(path_name)
if isfile(path_name), delete(path_name); end
end
