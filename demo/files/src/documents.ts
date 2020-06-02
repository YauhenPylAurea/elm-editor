import {Document} from "./document.ts";
import {quantum_md, test_tex} from "./data.ts"


export const documents: Array<Document> = [
  {
    fileName: "quantum.md",
    id: "143d1170-f8ce-47b3-904d-e84191d3d717",
    content: quantum_md,
  },
  {
    fileName: "test.tex",
    id: "7a7e54a9-70d9-4263-ba02-cb685e1fdaf8",
    content: test_tex,
  },
];
