class_name Layers
## Layer visivi usati dal gioco (bitmask di VisualInstance3D.layers e Decal.cull_mask).
## File senza dipendenze apposta: lo possono usare tutti senza creare riferimenti circolari tra classi.

## Pavimento, muri, mondo: ricevono le macchie di sangue (Decal).
const WORLD := 1
## Armi in prima persona, nemici, gibs, effetti: il sangue non ci si proietta sopra.
const NO_BLOOD := 2
