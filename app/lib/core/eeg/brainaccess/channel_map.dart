/// Nazwy elektrod dla BrainAccess MAXI wg tabel 2 i 3 instrukcji kabli
/// (MAN-ELEC): indeks na module zlaczy (od 0) -> nazwa 10-20.
/// Zgodnosc z indeksami SDK nie jest potwierdzona pomiarem.
const maxiManufacturerNames = [
  'P8',
  'O2',
  'P4',
  'C4',
  'F8',
  'F4',
  'Oz',
  'Cz',
  'Fz',
  'Pz',
  'F3',
  'O1',
  'P7',
  'C3',
  'P3',
  'F7',
  'T8',
  'FC6',
  'CP6',
  'CP2',
  'PO4',
  'FC2',
  'AF4',
  'POz',
  'AFz',
  'AF3',
  'FC1',
  'FC5',
  'T7',
  'CP1',
  'CP5',
  'PO3',
];

List<String> numberedNames(int count) => [
  for (var i = 1; i <= count; i++) 'ch$i',
];
