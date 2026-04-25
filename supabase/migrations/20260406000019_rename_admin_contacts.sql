-- Rename admin contacts from "Admin V"/"Admin A" to "V"/"A"
UPDATE public.contatos SET nome = 'V' WHERE nome = 'Admin V' AND canal_origem = 'ADMIN';
UPDATE public.contatos SET nome = 'A' WHERE nome = 'Admin A' AND canal_origem = 'ADMIN';
