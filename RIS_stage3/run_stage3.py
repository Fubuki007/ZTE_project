"""Full-scale resumable SNR / angle-RMSE experiment; local runs require --smoke."""
import argparse
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import platform
import tempfile
import time
import traceback
import numpy as np
from threadpoolctl import threadpool_limits
from stage3_model import Config, Model, angle_errors
from streaming import Observation, simulate_block, reference_power, coarse_from_records

METHODS = ['DD FFT', 'DD joint refinement', 'Random RIS + joint refinement', 'Stage-3 optimized RIS']


def atomic_json(path, data):
    path = Path(path)
    temp = path.with_suffix(path.suffix+f'.{os.getpid()}.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')
    os.replace(temp, path)


def code_hash():
    h = hashlib.sha256()
    for name in ('stage3_model.py', 'streaming.py', 'run_stage3.py'):
        h.update((Path(__file__).parent/name).read_bytes())
    return h.hexdigest()


def run_case(cfg, snr, trial, directory, batch=128):
    started = time.monotonic()
    model = Model(cfg)
    seed = cfg.seed+trial*10000+int(round((snr+100)*10))
    ref = reference_power(cfg, batch)
    variance = ref/10**(snr/10)
    times_c = np.arange(cfg.lc)*cfg.symbol_time
    times_f = np.arange(cfg.lc,cfg.lc+cfg.lf)*cfg.symbol_time
    truth = np.array(cfg.truth)
    def log(message):
        print(f'SNR={snr:+g} MC={trial+1} elapsed={time.monotonic()-started:.1f}s {message}',flush=True)
    with tempfile.TemporaryDirectory(prefix=f'case_{os.getpid()}_',dir=directory) as work:
        path=Path(work)
        yc=simulate_block(cfg,model.wzf,None,times_c,variance,seed,path/'coarse.npy',batch)
        rc=dict(y=yc,w=model.wzf,phase=None,times=times_c)
        coarse=coarse_from_records(cfg,[rc])
        log('coarse estimate complete')
        w,phase,design=model.design(coarse)
        log('joint beam/RIS optimization complete')
        generator=np.random.default_rng(seed+2)
        levels=np.exp(2j*np.pi*np.arange(2**cfg.bits)/2**cfg.bits)
        random_phase=generator.choice(levels,len(model.ris))
        estimates=[]
        diagnostics=[]
        for mode,(wm,pm,paths) in enumerate([(model.wzf,None,False),
                                             (model.wzf,random_phase,True),(w,phase,True)]):
            yf=simulate_block(cfg,wm,pm,times_f,variance,seed+1,path/f'fine_{mode}.npy',batch)
            rf=dict(y=yf,w=wm,phase=pm,times=times_f)
            obs=Observation(cfg,[rc,rf],batch)
            if mode==0:
                # Equal total CPI baseline: use both blocks for legacy FFT.
                full_fft=coarse_from_records(cfg,[rc,rf])
                estimates.append(full_fft)
                diagnostics.append(dict(method='full-CPI DD FFT'))
                initial=full_fft
            else:
                initial=coarse
            estimate,info=obs.refine(initial,paths)
            estimates.append(estimate)
            diagnostics.append(info)
            log(f'{METHODS[mode+1]} complete')
            del obs,rf,yf
            (path/f'fine_{mode}.npy').unlink()
        del rc,yc
    errors=[]
    geodesic=[]
    for est in estimates:
        e,g=angle_errors(est,truth)
        errors.append(e.tolist())
        geodesic.append(g.tolist())
    result=dict(snr_db=snr,trial=trial,seed=seed,methods=METHODS,estimates=np.array(estimates).tolist(),
                angular_errors_deg=errors,geodesic_errors_deg=geodesic,
                coarse=coarse.tolist(),diagnostics=diagnostics,design=design,
                noise_reference_power=ref,noise_variance=variance,
                elapsed_seconds=time.monotonic()-started,
                min_sinr_by_method=[float(np.min(model.sinr(model.wzf,None))),
                                    float(np.min(model.sinr(model.wzf,random_phase))),design['min_sinr']])
    return result,w,phase


def aggregate(output, manifest, partial=False):
    import csv
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    cfg=manifest['config']
    snrs=manifest['snr_db']
    nmc=manifest['mc']
    rmse=np.full((len(snrs),len(METHODS)),np.nan)
    ci=np.full((len(snrs),len(METHODS),2),np.nan)
    counts=[]
    rows=[]
    rng=np.random.default_rng(20261012)
    for si,snr in enumerate(snrs):
        records=[]
        for trial in range(nmc):
            f=output/'samples'/f'snr_{si:02d}_mc_{trial:04d}.json'
            if f.exists():
                r=json.loads(f.read_text(encoding='utf-8'))
                if r['manifest_id'] != manifest['id']:
                    raise RuntimeError(f'Incompatible checkpoint: {f}')
                records.append(r)
        counts.append(len(records))
        if not records:
            continue
        e=np.array([r['angular_errors_deg'] for r in records]) # MC,method,target,theta/phi
        squared=np.mean(e**2,axis=(2,3))
        rmse[si]=np.sqrt(np.mean(squared,axis=0))
        samples=rng.integers(0,len(records),size=(1000,len(records)))
        boot=np.sqrt(np.mean(squared[samples],axis=1))
        ci[si]=np.quantile(boot,[.025,.975],axis=0).T
        for m,method in enumerate(METHODS):
            theta=np.sqrt(np.mean(e[:,m,:,0]**2))
            phi=np.sqrt(np.mean(e[:,m,:,1]**2))
            geo=np.sqrt(np.mean(np.array([r['geodesic_errors_deg'][m] for r in records])**2))
            rows.append(dict(snr_db=snr,method=method,mc_completed=len(records),
                             angle_rmse_deg=rmse[si,m],theta_rmse_deg=theta,phi_rmse_deg=phi,
                             geodesic_rmse_deg=geo,ci95_low=ci[si,m,0],ci95_high=ci[si,m,1],
                             outlier_rate=float(np.mean(np.any(np.abs(e[:,m])>5,axis=(1,2))))))
    complete=all(n==nmc for n in counts)
    if not complete and not partial:
        raise RuntimeError(f'Incomplete experiment: {counts}, expected {nmc} per SNR')
    if rows:
        with (output/'angle_rmse_vs_snr.csv').open('w',newline='',encoding='utf-8') as f:
            writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
    plt.rcParams.update({'font.family':'DejaVu Sans','font.size':12})
    fig,ax=plt.subplots(figsize=(9.2,5.8),constrained_layout=True)
    colors=['#6b7280','#3478b5','#b18a32','#ca4260']
    for m,method in enumerate(METHODS):
        ax.semilogy(snrs,rmse[:,m],marker=['s','^','D','o'][m],color=colors[m],label=method,lw=2,ms=6)
        if nmc>1:
            ax.fill_between(snrs,ci[:,m,0],ci[:,m,1],color=colors[m],alpha=.12)
    ax.set(xlabel='SNR (dB)',ylabel='Angle RMSE (degree)',xlim=(min(snrs),max(snrs)))
    ax.set_xticks(snrs)
    ax.grid(True,which='both',alpha=.25)
    ax.legend(fontsize=10)
    status='FULL SCALE' if manifest['profile']=='full' else 'LOCAL SMOKE - NOT FINAL RESULTS'
    subtitle=f"{cfg['ns']:,} subcarriers | {cfg['rx_nx']*cfg['rx_ny']} Rx | {cfg['lc']+cfg['lf']} symbols | MC {min(counts)}-{max(counts)}/{nmc}"
    ax.set_title(status+(' - INCOMPLETE' if not complete else '')+'\n'+subtitle,fontsize=11)
    fig.savefig(output/'angle_rmse_vs_snr.png',dpi=220)
    fig.savefig(output/'angle_rmse_vs_snr.svg')
    plt.close(fig)
    atomic_json(output/'progress.json',dict(complete=complete,counts=counts,total_completed=sum(counts),
                                           total_expected=nmc*len(snrs),snr_db=snrs))
    return complete


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--smoke',action='store_true',help='Only allowed profile on Windows/local laptop')
    parser.add_argument('--mc',type=int,default=None)
    parser.add_argument('--snr',default='-30,-25,-20,-15,-10,-5,0,5,10,15,20')
    parser.add_argument('--output',type=Path,default=Path(__file__).parent/'results_full_mc100')
    parser.add_argument('--worker',type=int,default=0)
    parser.add_argument('--workers',type=int,default=1)
    parser.add_argument('--threads',type=int,default=4)
    parser.add_argument('--batch',type=int,default=128)
    parser.add_argument('--aggregate-only',action='store_true')
    parser.add_argument('--partial',action='store_true')
    args=parser.parse_args()
    if platform.system()=='Windows' and not args.smoke and not args.aggregate_only:
        parser.error('Full experiments run on the server. Use --smoke locally.')
    if not 0<=args.worker<args.workers or args.batch<1:
        parser.error('Invalid worker index/count or batch size')
    cfg=Config()
    if args.smoke:
        cfg.ns=512;cfg.lc=32;cfg.lf=32;cfg.rx_nx=4;cfg.rx_ny=4
        cfg.ao_iterations=2;cfg.sca_iterations=2;cfg.refinement_iterations=8
        if args.output.name=='results_full_mc100': args.output=Path(__file__).parent/'results_smoke'
    mc=args.mc if args.mc is not None else (1 if args.smoke else 100)
    snrs=[float(s) for s in args.snr.split(',')]
    if mc<1 or len(snrs)<1 or not np.all(np.isfinite(snrs)) or any(np.diff(snrs)<=0):
        parser.error('MC must be positive and SNR values strictly increasing and finite')
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'samples').mkdir(exist_ok=True)
    if args.aggregate_only:
        manifest=json.loads((args.output/'manifest.json').read_text(encoding='utf-8'))
        aggregate(args.output,manifest,args.partial)
        return
    identity=dict(config=asdict(cfg),snr_db=snrs,mc=mc,profile='smoke' if args.smoke else 'full',
                  code_sha256=code_hash(),batch=args.batch,
                  angle_metric='sqrt(mean over MC,targets,theta/phi of squared degree error)',
                  noise_reference='mean DD-only ZF echo power, same variance in every method',
                  waveform='known unit-modulus QPSK; observations losslessly demodulated',
                  velocity_model='BS-radial constant velocity; geometry frozen within CPI',
                  target_count='two known targets',self_interference=False)
    digest=hashlib.sha256(json.dumps(identity,sort_keys=True).encode()).hexdigest()
    identity['id']=digest
    manifest_path=args.output/'manifest.json'
    if manifest_path.exists():
        if json.loads(manifest_path.read_text(encoding='utf-8'))['id']!=digest:
            raise RuntimeError('Output contains a different experiment/code; use a new output directory')
    else:
        atomic_json(manifest_path,identity)
    print(f"PROFILE={identity['profile']} Ns={cfg.ns} Rx={cfg.rx_nx*cfg.rx_ny} L={cfg.lc}+{cfg.lf} MC={mc} SNR={snrs}",flush=True)
    completed=0
    with threadpool_limits(limits=args.threads):
        for trial in range(mc):
            for si,snr in enumerate(snrs):
                if (trial*len(snrs)+si)%args.workers!=args.worker:
                    continue
                dest=args.output/'samples'/f'snr_{si:02d}_mc_{trial:04d}.json'
                if dest.exists():
                    saved=json.loads(dest.read_text(encoding='utf-8'))
                    if saved['manifest_id']!=digest: raise RuntimeError('Checkpoint identity mismatch')
                    completed+=1
                    continue
                result,w,phase=run_case(cfg,snr,trial,args.output,args.batch)
                result['manifest_id']=digest
                np.savez_compressed(dest.with_suffix('.npz'),w=w,phase=phase)
                atomic_json(dest,result)
                completed+=1
                print(f"SAVED={dest.name} worker={args.worker} completed={completed} seconds={result['elapsed_seconds']:.1f}",flush=True)
    atomic_json(args.output/f'worker_{args.worker}.done.json',dict(manifest_id=digest,completed=completed))
    if args.workers==1: aggregate(args.output,identity)


if __name__=='__main__':
    main()
