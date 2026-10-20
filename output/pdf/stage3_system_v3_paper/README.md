# Compact paper figures

Three separate English figures, with captions outside the image area:

- `A_system_model_paper`: transceiver and RIS-assisted propagation.
- `B_target_geometry_paper`: target geometry and angle definitions.
- `C_sensing_paths_paper`: DD, RD, DR, and RR paths.

PDFs are vector graphics with embedded Times New Roman fonts. A and C have a native width of 178 mm; B has a native width of 85 mm. PNGs are rendered at 400 dpi. SVGs retain editable shapes and text.

`captions.tex` contains optional figure snippets for a two-column manuscript using `graphicx`. `draw_paper_figures.py` regenerates the PDF and SVG files using Python and ReportLab.

The figure follows Section II, equations (1)-(27), of the supplied stage-3 manuscript. The left-hand waveform branch is a known digital reference for sensing, not an over-the-air feedback path. OFDM Tx and OFDM Rx summarize the modulation and demodulation operations without adding a separate sensing waveform. A representative target and user are drawn; geometry and array-element counts are schematic. The receiver is a uniform planar array. The RR sketch uses one physical RIS on both legs. No experiments or simulations are run.
