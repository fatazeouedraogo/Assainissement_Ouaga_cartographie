const REJECT = {
  hors_zone: 'position hors de la zone',
  photo_absente: 'photo manquante',
  photo_illisible: 'photo illisible',
  doublon_meme_auteur: 'vous avez déjà signalé ce lieu',
  photo_reutilisee: 'photo déjà utilisée ailleurs',
};
const FLAGS = {
  photo_floue: 'photo floue',
  photo_sombre: 'photo sombre',
  contenu_douteux: 'contenu de la photo douteux',
  photo_copie_suspecte: 'photo proche d’un autre signalement',
  gps_imprecis: 'position imprécise',
  deplacement_impossible: 'déplacement trop rapide',
  analyse_indisponible: 'analyse indisponible',
};
export const rejectText = (c) => REJECT[c] || c;
export const flagText = (c) => FLAGS[c] || c;
