:- encoding(utf8).
:- ensure_loaded('rules.pl').
:- use_module(library(random),
              [getrand/1, setrand/1, random_member/2,
               random_permutation/2, random_between/3]).

% Gera apenas cenários com pelo menos uma sequência válida de atribuições.
% Os médicos, pacientes e a ocupação de construção são temporários:
% a interface recebe as listas iniciais, com todos os pacientes na espera.
gerar_cenario_interface(Numero_Medicos, Numero_Pacientes, Semente,
                       Medicos, Pacientes, Limite) :-
    Numero_Medicos > 0,
    Numero_Pacientes >= 0,
    setup_call_cleanup(
        getrand(Estado_Aleatorio),
        (   set_random(seed(Semente)),
            snapshot((
                sortear_medicos(Numero_Medicos, Medicos),
                retractall(medico(_, _, _)),
                retractall(paciente(_, _, _, _)),
                maplist(cadastrar_medico_interface, Medicos),
                limite_minimo(Minimo),
                Media is (Numero_Pacientes + Numero_Medicos - 1)
                         // Numero_Medicos,
                Limite is max(Minimo, Media),
                retractall(limite_minimo(_)),
                assertz(limite_minimo(Limite)),
                estado_inicial(estado([], Filas)),
                sortear_pacientes(1, Numero_Pacientes, Filas, Pacientes)
            ))
        ),
        setrand(Estado_Aleatorio)
    ).

% A lista vem dos perfis cadastrados, sem duplicar esse catálogo no Python.
% Evita repetir especialidades enquanto ainda há opções não sorteadas.
sortear_medicos(Quantidade, [[m1, [Geral]] | Especialistas]) :-
    once(generalista(Geral)),
    findall(Especialidade,
        (   perfil(Especialidade, Risco, Grupo),
            \+ generalista(Especialidade),
            taxa_critica(Risco, _),
            grupo_critico(Grupo, _)
        ), Opcoes_Repetidas),
    sort(Opcoes_Repetidas, Opcoes),
    (   Quantidade > 1, Opcoes == []
    ->  throw(error(existence_error(perfis_de_especialistas, facts),
                    gerar_cenario_interface/6))
    ;   true
    ),
    random_permutation(Opcoes, Sorteadas),
    sortear_especialistas(2, Quantidade, Sorteadas, Opcoes, Especialistas).

sortear_especialistas(Numero, Total, _, _, []) :-
    Numero > Total, !.
sortear_especialistas(Numero, Total, [], Opcoes, Medicos) :-
    !,
    random_permutation(Opcoes, Sorteadas),
    sortear_especialistas(Numero, Total, Sorteadas, Opcoes, Medicos).
sortear_especialistas(Numero, Total, [Primeira | Resto], Opcoes,
                     [[Id, Especialidades] | Medicos]) :-
    atom_concat(m, Numero, Id),
    length(Resto, Disponiveis),
    Restantes is Total - Numero,
    random_between(1, 2, Quantidade),
    (   Quantidade =:= 2, Disponiveis > Restantes
    ->  Resto = [Segunda | Proximas],
        Especialidades = [Primeira, Segunda]
    ;   Especialidades = [Primeira],
        Proximas = Resto
    ),
    Proximo is Numero + 1,
    sortear_especialistas(Proximo, Total, Proximas, Opcoes, Medicos).

sortear_pacientes(Numero, Total, _, []) :-
    Numero > Total, !.
sortear_pacientes(Numero, Total, Filas,
                  [[Id, Risco, Grupos] | Pacientes]) :-
    atom_concat(p, Numero, Id),
    findall([Risco_Candidato, Grupos_Candidatos, Medicos_Possiveis],
        (   taxa_critica(Risco_Candidato, _),
            grupos_candidatos(Grupos_Candidatos),
            snapshot((
                assertz(paciente(Id, Id, Risco_Candidato, Grupos_Candidatos)),
                findall(Medico, pode_atender(Id, Medico, Filas), Medicos_Possiveis),
                Medicos_Possiveis = [_ | _]
            ))
        ), Candidatos),
    (   Candidatos == []
    ->  throw(error(domain_error(cenario_com_cobertura, Id),
                    gerar_cenario_interface/6))
    ;   random_member([Risco, Grupos, Medicos], Candidatos)
    ),
    random_member(Id_Medico, Medicos),
    assertz(paciente(Id, Id, Risco, Grupos)),
    atualizar_fila(Id, Id_Medico, Filas, Novas_Filas),
    Proximo is Numero + 1,
    sortear_pacientes(Proximo, Total, Novas_Filas, Pacientes).

% 'geral' permanece exclusivo. Pares devem respeitar as incompatibilidades.
grupos_candidatos([geral]) :- grupo_critico(geral, _).
grupos_candidatos([Grupo]) :-
    grupo_critico(Grupo, _), Grupo \== geral.
grupos_candidatos([Primeiro, Segundo]) :-
    grupo_critico(Primeiro, _), Primeiro \== geral,
    grupo_critico(Segundo, _), Segundo \== geral,
    Primeiro @< Segundo,
    \+ grupos_incompativeis(Primeiro, Segundo),
    \+ grupos_incompativeis(Segundo, Primeiro).

% As duas consultas acima bloqueiam o par independentemente da ordem.
grupos_incompativeis(gestante, crianca).
grupos_incompativeis(gestante, idoso).
grupos_incompativeis(crianca, idoso).
